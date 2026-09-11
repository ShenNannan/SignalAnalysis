classdef DataReaderFactory
% DataReaderFactory - 数据读取工厂
%
% 两阶段设计：
%   阶段一 ImportToStandard：原始文件 → 标准化 .mat + _meta.json + _review.xlsx
%   阶段二 LoadStandard：标准化 .mat → Dataset
%
% 设计原则：
%   - 解析器只提取原始数据矩阵和列名
%   - 采样率、单位、描述由用户在 UI 界面提供
%   - 文件头中的元数据（如列名）仍然提取

    methods (Static)
        function matPath = ImportToStandard(filePath, outputDir, varargin)
        % ImportToStandard 阶段一：原始文件 → 标准化 .mat + _meta.json + _review.xlsx
        %
        % 可选参数：
        %   ColumnNames   - cell 覆盖列名
        %   Units         - cell 每列单位
        %   Descriptions  - cell 每列描述
        %   ForceFormat   - char 强制使用指定解析器
        %   NoCache       - logical 跳过缓存检查

            p = inputParser;
            addRequired(p, 'filePath', @ischar);
            addRequired(p, 'outputDir', @ischar);
            addParameter(p, 'ColumnNames', {}, @iscell);
            addParameter(p, 'Units', {}, @iscell);
            addParameter(p, 'Descriptions', {}, @iscell);
            addParameter(p, 'ForceFormat', '', @ischar);
            addParameter(p, 'NoCache', false, @islogical);
            parse(p, filePath, outputDir, varargin{:});

            opts = p.Results;

            % 确保输出目录存在
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            % 检查缓存
            if ~opts.NoCache && DataReaderFactory.HasValidCache(filePath, outputDir)
                [~, baseName] = fileparts(filePath);
                matPath = fullfile(outputDir, [baseName '_standardized.mat']);
                return;
            end

            % 解析（只提取数据矩阵和列名）
            if ~isempty(opts.ForceFormat)
                [data, columnNames, formatTag, warnings] = ...
                    DataReaderFactory.ParseWithForceFormat(filePath, opts.ForceFormat);
            else
                [data, columnNames, formatTag, warnings] = ...
                    DataReaderFactory.AutoDetectAndParse(filePath);
            end

            % 结构验证
            DataReaderFactory.ValidateStructure(data);

            % 合并用户指定的列名
            if ~isempty(opts.ColumnNames)
                columnNames = opts.ColumnNames;
            end

            % 生成默认列名
            nCols = size(data, 2);
            if isempty(columnNames)
                columnNames = arrayfun(@(i) sprintf('Channel_%d', i), 1:nCols, 'UniformOutput', false);
                warnings{end+1} = 'Column names auto-generated';
            end

            % 采样率由用户提供，默认为空（Dataset 默认 1Hz）
            sa_data_matrix = data;
            sa_sample_rate = [];
            sa_column_names = columnNames;
            sa_units = opts.Units;
            sa_descriptions = opts.Descriptions;
            sa_source_file = filePath;
            sa_source_format = formatTag;
            sa_import_time = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<DATST>

            % 保存 .mat
            [~, baseName] = fileparts(filePath);
            matPath = fullfile(outputDir, [baseName '_standardized.mat']);
            save(matPath, ...
                'sa_data_matrix', 'sa_sample_rate', 'sa_column_names', ...
                'sa_units', 'sa_descriptions', 'sa_source_file', ...
                'sa_source_format', 'sa_import_time');

            % 保存 _meta.json
            meta = struct();
            meta.source_file = filePath;
            meta.source_format = formatTag;
            meta.import_time = sa_import_time;
            meta.row_count = size(data, 1);
            meta.column_count = nCols;
            meta.warnings = {warnings};

            columns = cell(1, nCols);
            for i = 1:nCols
                col = struct();
                col.index = i;
                col.name = columnNames{i};
                if i <= length(sa_units) && ~isempty(sa_units{i})
                    col.unit = sa_units{i};
                else
                    col.unit = '';
                end
                if i <= length(sa_descriptions) && ~isempty(sa_descriptions{i})
                    col.description = sa_descriptions{i};
                else
                    col.description = '';
                end
                columns{i} = col;
            end
            meta.columns = [columns{:}];

            jsonPath = fullfile(outputDir, [baseName '_standardized_meta.json']);
            DataReaderFactory.WriteJson(jsonPath, meta);

            % 自动生成 Excel 审查文件
            xlsxPath = fullfile(outputDir, [baseName '_review.xlsx']);
            try
                DataReaderFactory.ExportToExcel(matPath, xlsxPath);
            catch
                % Excel 生成失败不影响主流程
            end
        end

        function dataset = LoadStandard(matPath)
        % LoadStandard 阶段二：标准化 .mat → Dataset
        %
        % 加载 .mat + _meta.json，构造 Dataset
        % 优先级：JSON 的 columns[].unit/description 覆盖 .mat 的 sa_units/sa_descriptions

            loaded = load(matPath);

            if ~isfield(loaded, 'sa_data_matrix')
                error('SignalAnalysis:DataReaderFactory:InvalidMat', ...
                    'Missing sa_data_matrix in %s', matPath);
            end

            data = loaded.sa_data_matrix;
            columnNames = loaded.sa_column_names;
            sourcePath = loaded.sa_source_file;
            formatTag = loaded.sa_source_format;

            sampleRate = [];
            if isfield(loaded, 'sa_sample_rate')
                sampleRate = loaded.sa_sample_rate;
            end

            units = {};
            descriptions = {};
            if isfield(loaded, 'sa_units')
                units = loaded.sa_units;
            end
            if isfield(loaded, 'sa_descriptions')
                descriptions = loaded.sa_descriptions;
            end

            % 读取 _meta.json，用 columns 数组覆盖 units/descriptions/sampleRate
            metadata = struct();
            [~, baseName] = fileparts(matPath);
            jsonPath = fullfile(fileparts(matPath), [baseName '_meta.json']);
            if exist(jsonPath, 'file')
                try
                    jsonText = fileread(jsonPath);
                    meta = jsondecode(jsonText);
                    metadata.json = meta;

                    % 从 JSON 读取采样率（如果 .mat 为空）
                    if isempty(sampleRate) && isfield(meta, 'sample_rate') && ~isempty(meta.sample_rate)
                        sampleRate = meta.sample_rate;
                    end

                    % 从 JSON 的 columns 数组读取 unit/description
                    if isfield(meta, 'columns') && isstruct(meta.columns)
                        nCols = size(data, 2);
                        units = cell(1, nCols);
                        descriptions = cell(1, nCols);
                        for c = 1:length(meta.columns)
                            if c <= nCols
                                if isfield(meta.columns(c), 'unit')
                                    units{c} = meta.columns(c).unit;
                                end
                                if isfield(meta.columns(c), 'description')
                                    descriptions{c} = meta.columns(c).description;
                                end
                            end
                        end
                    end
                catch
                end
            end

            dataset = Dataset(data, columnNames, sampleRate, sourcePath, formatTag, metadata, units, descriptions);
        end

        function ExportToExcel(matPath, xlsxPath)
        % ExportToExcel 导出到 Excel 供用户编辑
        %
        % Excel 格式（仅列名 + 数据）：
        %   第1行：列名（用户可编辑）
        %   第2行起：数据矩阵

            loaded = load(matPath);
            data = loaded.sa_data_matrix;
            columnNames = loaded.sa_column_names;
            nCols = size(data, 2);
            nRows = size(data, 1);

            % 构建写入矩阵：1行列名 + N行数据
            allData = cell(nRows + 1, nCols);
            for c = 1:nCols
                if ~isempty(columnNames) && c <= length(columnNames)
                    allData{1, c} = columnNames{c};
                else
                    allData{1, c} = '';
                end
            end
            for r = 1:nRows
                for c = 1:nCols
                    allData{r+1, c} = data(r, c);
                end
            end

            if exist('writecell', 'file')
                writecell(allData, xlsxPath);
            else
                xlswrite(xlsxPath, allData);
            end
        end

        function matPath = ImportFromExcel(xlsxPath, outputDir, varargin)
        % ImportFromExcel 从 Excel 重新导入（用户编辑后）
        %
        % Excel 格式（仅列名 + 数据）：
        %   第1行：列名
        %   第2行起：数据
        %
        % 列名逻辑：
        %   Excel 有列名 → 使用 Excel 列名
        %   Excel 列名全空 → 保留已有 .mat 的列名
        %
        % 采样率、单位、描述：从已有 .mat 保留

            p = inputParser;
            addRequired(p, 'xlsxPath', @ischar);
            addRequired(p, 'outputDir', @ischar);
            parse(p, xlsxPath, outputDir, varargin{:});

            % 读取 Excel
            if exist('readcell', 'file')
                raw = readcell(xlsxPath);
            else
                [~, ~, raw] = xlsread(xlsxPath); %#ok<XLSRD>
            end

            nCols = size(raw, 2);
            nDataRows = size(raw, 1) - 1;

            % 第1行列名
            excelColNames = cell(1, nCols);
            for c = 1:nCols
                val = raw{1, c};
                if (ischar(val) || isstring(val)) && ~isempty(strtrim(char(val)))
                    excelColNames{c} = strtrim(char(val));
                end
            end

            % 第2行起数据
            data = zeros(nDataRows, nCols);
            for r = 1:nDataRows
                for c = 1:nCols
                    val = raw{r + 1, c};
                    if isnumeric(val) && isscalar(val)
                        data(r, c) = val;
                    else
                        data(r, c) = NaN;
                    end
                end
            end

            % 确定输出路径
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end
            [~, baseName] = fileparts(xlsxPath);
            matPath = fullfile(outputDir, [baseName '_standardized.mat']);

            % 列名逻辑：Excel 有 → 用 Excel 的；Excel 空 → 保留 .mat 的
            hasExcelColNames = any(cellfun(@(s) ~isempty(s), excelColNames));
            if hasExcelColNames
                columnNames = excelColNames;
            elseif exist(matPath, 'file')
                try
                    old = load(matPath);
                    if isfield(old, 'sa_column_names') && ~isempty(old.sa_column_names)
                        columnNames = old.sa_column_names;
                    else
                        columnNames = {};
                    end
                catch
                    columnNames = {};
                end
            else
                columnNames = {};
            end

            % 保留已有 .mat 的元数据
            sampleRate = [];
            units = {};
            descriptions = {};
            if exist(matPath, 'file')
                try
                    old = load(matPath);
                    if isfield(old, 'sa_sample_rate'), sampleRate = old.sa_sample_rate; end
                    if isfield(old, 'sa_units'), units = old.sa_units; end
                    if isfield(old, 'sa_descriptions'), descriptions = old.sa_descriptions; end
                catch
                end
            end

            % 保存
            sa_data_matrix = data; %#ok<NASGU>
            sa_sample_rate = sampleRate; %#ok<NASGU>
            sa_column_names = columnNames; %#ok<NASGU>
            sa_units = units; %#ok<NASGU>
            sa_descriptions = descriptions; %#ok<NASGU>
            sa_source_file = xlsxPath; %#ok<NASGU>
            sa_source_format = 'excel'; %#ok<NASGU>
            sa_import_time = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<NASGU,DATST>

            save(matPath, ...
                'sa_data_matrix', 'sa_sample_rate', 'sa_column_names', ...
                'sa_units', 'sa_descriptions', 'sa_source_file', ...
                'sa_source_format', 'sa_import_time');

            % 保存 _meta.json
            meta = struct();
            meta.source_file = xlsxPath;
            meta.source_format = 'excel';
            meta.import_time = sa_import_time;
            meta.row_count = nDataRows;
            meta.column_count = nCols;
            meta.warnings = {};

            jsonPath = fullfile(outputDir, [baseName '_standardized_meta.json']);
            DataReaderFactory.WriteJson(jsonPath, meta);
        end

        function valid = HasValidCache(filePath, outputDir)
        % HasValidCache 检查是否有有效缓存
        %
        % 有效条件：
        %   1. 标准化.mat 存在
        %   2. 同名_meta.json 存在
        %   3. .mat 修改时间 >= 原始文件修改时间

            [~, baseName] = fileparts(filePath);
            matPath = fullfile(outputDir, [baseName '_standardized.mat']);
            jsonPath = fullfile(outputDir, [baseName '_standardized_meta.json']);

            valid = false;
            if ~exist(matPath, 'file')
                return;
            end
            if ~exist(jsonPath, 'file')
                return;
            end

            % 检查时间戳
            matInfo = dir(matPath);
            srcInfo = dir(filePath);
            if isempty(matInfo) || isempty(srcInfo)
                return;
            end

            valid = matInfo.datenum >= srcInfo.datenum;
        end

        function files = ListStandardFiles(directory)
        % ListStandardFiles 列出目录下所有标准化.mat文件
            listing = dir(fullfile(directory, '*_standardized.mat'));
            files = cell(1, length(listing));
            for i = 1:length(listing)
                files{i} = fullfile(directory, listing(i).name);
            end
        end

        function results = BatchImportFolder(rootDir, varargin)
        % BatchImportFolder 遍历根文件夹下所有子文件夹，智能导入数据
        %
        % 子文件夹处理逻辑：
        %   情况A：单个文件 → 直接导入
        %   情况B：多个 N×1 向量 → 合并为 N×M 矩阵
        %   情况C：多个 N×M 文件 → 每个文件单独导入
        %
        % 返回：results 结构体数组，每项包含：
        %   .name    - 数据集名称（子文件夹名或文件名）
        %   .matPath - 标准化 .mat 文件路径
        %   .matrices - 合并前的原始文件路径（情况B）

            p = inputParser;
            addRequired(p, 'rootDir', @ischar);
            parse(p, rootDir, varargin{:});

            extensions = {'.dat', '.csv', '.txt', '.xlsx', '.mat'};
            results = struct('name', {}, 'matPath', {});

            % 规范化路径（去除末尾分隔符）
            rootDir = char(rootDir);
            if rootDir(end) == filesep || rootDir(end) == '/'
                rootDir(end) = [];
            end

            % 验证目录存在
            if ~exist(rootDir, 'dir')
                fprintf('[DataReaderFactory] 目录不存在: %s\n', rootDir);
                return;
            end

            % 列出根目录下的子文件夹
            listing = dir(rootDir);
            subdirs = {};
            subnames = {};
            for i = 1:length(listing)
                if listing(i).isdir && ~strcmp(listing(i).name, '.') && ~strcmp(listing(i).name, '..')
                    subdirs{end+1} = fullfile(rootDir, listing(i).name); %#ok<AGROW>
                    subnames{end+1} = listing(i).name; %#ok<AGROW>
                end
            end

            % 如果没有子文件夹，扫描根目录本身
            if isempty(subdirs)
                subdirs = {rootDir};
                [~, subnames{1}] = fileparts(rootDir);
            end

            % 遍历每个子文件夹
            for d = 1:length(subdirs)
                subdir = subdirs{d};
                subname = subnames{d};

                try
                    subResults = DataReaderFactory.ProcessSubfolder(subdir, subname, extensions);
                    results = [results, subResults]; %#ok<AGROW>
                catch ME
                    fprintf('[DataReaderFactory] 子文件夹 %s 处理失败: %s\n', subname, ME.message);
                end
            end

            if isempty(results)
                fprintf('[DataReaderFactory] 未找到可导入的数据: %s\n', rootDir);
            end
        end

        function UpdateSampleRateInMat(matPath, sampleRate)
        % UpdateSampleRateInMat 更新 .mat 文件中的采样率
        %
        % 用于用户在 UI 界面设置采样率后，回写到 .mat 文件

            loaded = load(matPath);
            sa_sample_rate = sampleRate; %#ok<NASGU>

            % 保存所有原有变量，更新采样率
            vars = fieldnames(loaded);
            saveArgs = {};
            for i = 1:length(vars)
                if strcmp(vars{i}, 'sa_sample_rate')
                    continue;
                end
                saveArgs{end+1} = vars{i}; %#ok<AGROW>
                saveArgs{end+1} = loaded.(vars{i}); %#ok<AGROW>
            end
            saveArgs{end+1} = 'sa_sample_rate';
            saveArgs{end+1} = sampleRate;

            save(matPath, saveArgs{:});
        end

        function SaveMetadata(matPath, sampleRate, units, descriptions)
        % SaveMetadata 保存元数据到 _meta.json + 同步更新 .mat
        %
        % 用于 UI 界面编辑元数据后调用
        %
        % 输入：
        %   matPath      - .mat 文件路径
        %   sampleRate   - 采样率（可为空）
        %   units        - cell {1×M} 单位
        %   descriptions - cell {1×M} 描述

            loaded = load(matPath);
            nCols = size(loaded.sa_data_matrix, 2);
            columnNames = loaded.sa_column_names;

            % 更新 .mat 中的 units/descriptions/sampleRate
            loaded.sa_sample_rate = sampleRate;
            loaded.sa_units = units;
            loaded.sa_descriptions = descriptions;

            sa_data_matrix = loaded.sa_data_matrix; %#ok<NASGU>
            sa_sample_rate = loaded.sa_sample_rate; %#ok<NASGU>
            sa_column_names = loaded.sa_column_names; %#ok<NASGU>
            sa_units = loaded.sa_units; %#ok<NASGU>
            sa_descriptions = loaded.sa_descriptions; %#ok<NASGU>
            sa_source_file = loaded.sa_source_file; %#ok<NASGU>
            sa_source_format = loaded.sa_source_format; %#ok<NASGU>
            sa_import_time = loaded.sa_import_time; %#ok<NASGU>

            save(matPath, ...
                'sa_data_matrix', 'sa_sample_rate', 'sa_column_names', ...
                'sa_units', 'sa_descriptions', 'sa_source_file', ...
                'sa_source_format', 'sa_import_time');

            % 更新 _meta.json
            [~, baseName] = fileparts(matPath);
            jsonPath = fullfile(fileparts(matPath), [baseName '_meta.json']);

            meta = struct();
            if exist(jsonPath, 'file')
                try
                    jsonText = fileread(jsonPath);
                    meta = jsondecode(jsonText);
                catch
                end
            end

            meta.sample_rate = sampleRate;

            % 更新 columns 数组
            columns = cell(1, nCols);
            for c = 1:nCols
                col = struct();
                col.index = c;
                if ~isempty(columnNames) && c <= length(columnNames)
                    col.name = columnNames{c};
                else
                    col.name = '';
                end
                if ~isempty(units) && c <= length(units)
                    col.unit = units{c};
                else
                    col.unit = '';
                end
                if ~isempty(descriptions) && c <= length(descriptions)
                    col.description = descriptions{c};
                else
                    col.description = '';
                end
                columns{c} = col;
            end
            meta.columns = [columns{:}];

            DataReaderFactory.WriteJson(jsonPath, meta);
        end
    end

    methods (Static, Access = private)
        function results = ProcessSubfolder(subdir, subname, extensions)
        % ProcessSubfolder 处理单个子文件夹
        %
        % 情况A：单个文件 → 直接导入
        % 情况B：多个 N×1 → 合并
        % 情况C：多个 N×M → 每个单独导入
        %
        % 列名提取为 best-effort，失败保留为空

            results = struct('name', {}, 'matPath', {});

            % 查找数据文件，跳过已标准化的
            allFiles = FileExplorer.ListByExtension(subdir, extensions);
            files = {};
            for i = 1:length(allFiles)
                [~, fname, ~] = fileparts(allFiles{i});
                if contains(fname, '_standardized') || contains(fname, '_review') || contains(fname, '_params')
                    continue;
                end
                files{end+1} = allFiles{i}; %#ok<AGROW>
            end

            if isempty(files)
                return;
            end

            % 逐个解析
            parsed = {};
            for i = 1:length(files)
                try
                    [data, colNames, fmtTag, ~] = DataReaderFactory.AutoDetectAndParse(files{i});
                    % 确保 colNames 是 cell
                    if ~iscell(colNames)
                        colNames = {};
                    end
                    parsed{end+1} = struct('path', files{i}, 'data', data, ...
                        'colNames', {colNames}, 'formatTag', fmtTag, ...
                        'nCols', size(data, 2), 'nRows', size(data, 1)); %#ok<AGROW>
                catch
                    % 解析失败，跳过
                end
            end

            if isempty(parsed)
                return;
            end

            % 判断情况
            allSingleCol = all(cellfun(@(p) p.nCols == 1, parsed));

            if length(parsed) == 1
                % 情况A：单个文件
                p = parsed{1};
                colNames = p.colNames;
                matPath = DataReaderFactory.SaveSubfolderResult(...
                    p.data, colNames, subdir, subname, p.path, p.formatTag);
                results(end+1).name = subname;
                results(end).matPath = matPath;

            elseif allSingleCol
                % 情况B：多个 N×1 → 合并
                [merged, colNames] = DataReaderFactory.MergeVectors(parsed, subname);
                srcPaths = cellfun(@(p) p.path, parsed, 'UniformOutput', false);
                matPath = DataReaderFactory.SaveSubfolderResult(...
                    merged, colNames, subdir, subname, strjoin(srcPaths, ';'), 'merged');
                results(end+1).name = subname;
                results(end).matPath = matPath;

            else
                % 情况C：多个 N×M → 每个单独导入
                for i = 1:length(parsed)
                    p = parsed{i};
                    [~, fname] = fileparts(p.path);
                    dsName = [subname '_' fname];
                    colNames = p.colNames;
                    if isempty(colNames)
                        colNames = arrayfun(@(j) sprintf('%s_Channel_%d', dsName, j), ...
                            1:p.nCols, 'UniformOutput', false);
                    end
                    matPath = DataReaderFactory.SaveSubfolderResult(...
                        p.data, colNames, subdir, dsName, p.path, p.formatTag);
                    results(end+1).name = dsName; %#ok<AGROW>
                    results(end).matPath = matPath;
                end
            end
        end

        function [merged, colNames] = MergeVectors(parsed, subname)
        % MergeVectors 将多个 N×1 向量合并为 N×M 矩阵
        %
        % 按文件名排序，验证长度一致，列名 = 子文件夹名_文件名

            % 按文件名排序
            paths = cellfun(@(p) p.path, parsed, 'UniformOutput', false);
            [~, sortIdx] = sort(paths);
            parsed = parsed(sortIdx);

            % 验证长度一致
            nRows = parsed{1}.nRows;
            valid = true(1, length(parsed));
            for i = 1:length(parsed)
                if parsed{i}.nRows ~= nRows
                    valid(i) = false;
                end
            end
            parsed = parsed(valid);

            if isempty(parsed)
                error('SignalAnalysis:DataReaderFactory:MergeFailed', ...
                    'No vectors with consistent length to merge');
            end

            % 合并
            nCols = length(parsed);
            merged = zeros(nRows, nCols);
            colNames = cell(1, nCols);
            for i = 1:nCols
                merged(:, i) = parsed{i}.data(:, 1);
                [~, fname] = fileparts(parsed{i}.path);
                name = [subname '_' fname];
                if length(name) > 63
                    name = name(1:63);
                end
                colNames{i} = name;
            end
        end

        function matPath = SaveSubfolderResult(data, colNames, subdir, baseName, sourcePath, formatTag)
        % SaveSubfolderResult 保存子文件夹处理结果
        %
        % 生成：子文件夹名_standardized.mat + _meta.json + _review.xlsx

            nCols = size(data, 2);
            nRows = size(data, 1);

            % 构建列信息（unit/description 为空，用户通过 UI 或 JSON 编辑）
            columns = cell(1, nCols);
            for c = 1:nCols
                col = struct();
                col.index = c;
                if ~isempty(colNames) && c <= length(colNames)
                    col.name = colNames{c};
                else
                    col.name = '';
                end
                col.unit = '';
                col.description = '';
                columns{c} = col;
            end

            % 保存 .mat
            sa_data_matrix = data; %#ok<NASGU>
            sa_sample_rate = []; %#ok<NASGU>
            sa_column_names = colNames; %#ok<NASGU>
            sa_units = {}; %#ok<NASGU>
            sa_descriptions = {}; %#ok<NASGU>
            sa_source_file = sourcePath; %#ok<NASGU>
            sa_source_format = formatTag; %#ok<NASGU>
            sa_import_time = datestr(now, 'yyyy-mm-ddTHH:MM:SS'); %#ok<NASGU,DATST>

            matPath = fullfile(subdir, [baseName '_standardized.mat']);
            save(matPath, ...
                'sa_data_matrix', 'sa_sample_rate', 'sa_column_names', ...
                'sa_units', 'sa_descriptions', 'sa_source_file', ...
                'sa_source_format', 'sa_import_time');

            % 保存 _meta.json
            meta = struct();
            meta.source_file = sourcePath;
            meta.source_format = formatTag;
            meta.import_time = sa_import_time;
            meta.row_count = nRows;
            meta.column_count = nCols;
            meta.sample_rate = [];
            meta.columns = [columns{:}];

            jsonPath = fullfile(subdir, [baseName '_standardized_meta.json']);
            DataReaderFactory.WriteJson(jsonPath, meta);

            % 保存 _review.xlsx
            xlsxPath = fullfile(subdir, [baseName '_review.xlsx']);
            try
                DataReaderFactory.ExportToExcel(matPath, xlsxPath);
            catch
            end
        end

        function [data, columnNames, formatTag, warnings] = AutoDetectAndParse(filePath)
        % AutoDetectAndParse 自动检测格式并解析
        %
        % 所有格式统一处理：解析 → 列名简化 → 去重

            [~, ~, ext] = fileparts(filePath);
            ext = lower(ext);

            warnings = {};

            switch ext
                case '.dat'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseDatFile(filePath);
                case '.txt'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseTxtFile(filePath);
                case '.csv'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseCsvFile(filePath);
                case '.mat'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseMatFile(filePath);
                case {'.xlsx', '.xls'}
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseExcelFile(filePath);
                case '.frfx'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseFrfxFile(filePath);
                otherwise
                    error('SignalAnalysis:DataReaderFactory:UnsupportedFormat', ...
                        'Unsupported file format: %s', ext);
            end

            % 统一处理列名：简化 + 去重
            if ~isempty(columnNames) && iscell(columnNames)
                for i = 1:length(columnNames)
                    if ~isempty(columnNames{i})
                        columnNames{i} = DataReaderFactory.SimplifyColumnName(columnNames{i});
                    end
                end
                columnNames = DataReaderFactory.DeduplicateNames(columnNames);
            end
        end

        function [data, columnNames, formatTag, warnings] = ParseWithForceFormat(filePath, forceFormat)
        % ParseWithForceFormat 使用指定格式解析

            warnings = {};
            switch lower(forceFormat)
                case 'fdot_binary'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseFdotBinary(filePath);
                case 'fdot_text'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseFdotText(filePath);
                case 'swpp_text'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseSwppText(filePath);
                case 'acs_swpp'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseAcsSwpp(filePath);
                case 'multi_section'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseMultiSection(filePath);
                case 'itps_text'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseItpsText(filePath);
                case 'acs_csv'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseAcsCsv(filePath);
                case 'mat'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseMatFile(filePath);
                case 'excel'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseExcelFile(filePath);
                case 'frfx'
                    [data, columnNames, formatTag] = ...
                        DataReaderFactory.ParseFrfxFile(filePath);
                otherwise
                    error('SignalAnalysis:DataReaderFactory:UnknownFormat', ...
                        'Unknown force format: %s', forceFormat);
            end
        end

        function [data, columnNames, formatTag] = ParseDatFile(filePath)
        % ParseDatFile .dat 格式自动探测
        %
        % 尝试顺序：FDOT二进制 → FDOT文本 → SWPP文本 → ACS SWPP → MultiSection
        % 使用置信度评分选择最佳解析结果

            parsers = {@DataReaderFactory.ParseFdotBinary, ...
                       @DataReaderFactory.ParseFdotText, ...
                       @DataReaderFactory.ParseSwppText, ...
                       @DataReaderFactory.ParseAcsSwpp, ...
                       @DataReaderFactory.ParseMultiSection};

            bestScore = -1;
            bestData = [];
            bestNames = {};
            bestTag = '';

            for i = 1:length(parsers)
                try
                    [d, n, t] = parsers{i}(filePath);

                    % 结构验证
                    DataReaderFactory.ValidateStructure(d);

                    % 置信度评分（基于数据质量，不依赖采样率）
                    score = DataReaderFactory.ComputeConfidence(d);

                    if score > bestScore
                        bestScore = score;
                        bestData = d;
                        bestNames = n;
                        bestTag = t;
                    end
                catch
                    % 解析失败，跳过
                end
            end

            if bestScore < 0
                error('SignalAnalysis:DataReaderFactory:AllParsersFailed', ...
                    'Could not parse .dat file with any known format: %s\nTry using ForceFormat.', filePath);
            end

            data = bestData;
            columnNames = bestNames;
            formatTag = bestTag;
        end

        function [data, columnNames, formatTag] = ParseTxtFile(filePath)
        % ParseTxtFile 纯数值文本格式

            data = load(filePath);
            if ~isnumeric(data) || ~ismatrix(data)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'Text file does not contain a numeric matrix');
            end
            columnNames = {};
            formatTag = 'itps_text';
        end

        function [data, columnNames, formatTag] = ParseCsvFile(filePath)
        % ParseCsvFile CSV 格式（7行头 + readmatrix）

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 读取头部
            headerLines = cell(1, 7);
            for i = 1:7
                headerLines{i} = fgetl(fid);
            end

            columnNames = {};

            % 关闭文件后用 readmatrix 读数据
            fclose(fid);
            clear cleanup;

            if exist('readmatrix', 'file')
                data = readmatrix(filePath, 'NumHeaderLines', 7);
            else
                data = csvread(filePath, 7, 0);
            end

            formatTag = 'acs_csv';
        end

        function [data, columnNames, formatTag] = ParseMatFile(filePath)
        % ParseMatFile .mat 格式：优先加载 sa_ 前缀变量

            loaded = load(filePath);

            % 优先检查 sa_ 前缀变量（标准化格式）
            if isfield(loaded, 'sa_data_matrix')
                data = loaded.sa_data_matrix;
                columnNames = {};
                if isfield(loaded, 'sa_column_names')
                    columnNames = loaded.sa_column_names;
                end
                formatTag = 'mat_standardized';
                return;
            end

            % 否则取第一个数值矩阵
            fields = fieldnames(loaded);
            data = [];
            for i = 1:length(fields)
                val = loaded.(fields{i});
                if isnumeric(val) && ismatrix(val)
                    data = double(val);
                    break;
                end
            end

            if isempty(data)
                error('SignalAnalysis:DataReaderFactory:NoNumericData', ...
                    'No numeric matrix found in .mat file');
            end

            columnNames = {};
            formatTag = 'mat';
        end

        function [data, columnNames, formatTag] = ParseExcelFile(filePath)
        % ParseExcelFile Excel 格式

            if exist('readmatrix', 'file')
                data = readmatrix(filePath);
            else
                data = xlsread(filePath); %#ok<XLSRD>
            end

            if ~isnumeric(data) || ~ismatrix(data)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'Excel file does not contain a numeric matrix');
            end

            columnNames = {};
            formatTag = 'excel';
        end

        function [data, columnNames, formatTag] = ParseFdotBinary(filePath)
        % ParseFdotBinary FDOT 二进制格式：[4字节列数][4字节行数][N×M×8字节double]

            fid = fopen(filePath, 'r', 'l');  % little-endian
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            header = fread(fid, 2, 'int32');
            if length(header) < 2
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'FDOT header too short');
            end

            nCols = header(1);
            nRows = header(2);

            validateattributes(nCols, {'numeric'}, {'positive', '<', 10000});
            validateattributes(nRows, {'numeric'}, {'positive', '<', 1e9});

            expectedBytes = 8 + nCols * nRows * 8;
            fseek(fid, 0, 'eof');
            actualBytes = ftell(fid);
            if actualBytes ~= expectedBytes
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'FDOT file size mismatch: expected %d, got %d', expectedBytes, actualBytes);
            end

            fseek(fid, 8, 'bof');
            data = fread(fid, [nCols, nRows], 'double')';

            if size(data, 1) ~= nRows || size(data, 2) ~= nCols
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'FDOT data size mismatch');
            end

            columnNames = {};
            formatTag = 'fdot_binary';
        end

        function [data, columnNames, formatTag] = ParseFdotText(filePath)
        % ParseFdotText FDOT 文本格式：1行标题 + 1行列名(tab分隔) + 数据行(tab分隔)
        %
        % 列名提取为 best-effort，失败返回空 cell

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 第1行：标题
            titleLine = fgetl(fid);
            if ~ischar(titleLine)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'FDOT text: empty file');
            end

            % 第2行：列名（best-effort，提取原始名称）
            columnNames = {};
            headerLine = fgetl(fid);
            if ischar(headerLine)
                try
                    headerLine = strrep(headerLine, sprintf('\r'), '');
                    rawParts = strsplit(headerLine, '\t');
                    if ischar(rawParts)
                        rawParts = {rawParts};
                    end
                    names = {};
                    for i = 1:length(rawParts)
                        name = strtrim(rawParts{i});
                        if isempty(name), continue; end
                        % 保留原始列名（含=>），由 AutoDetectAndParse 统一简化
                        names{end+1} = name; %#ok<AGROW>
                    end
                    if ~isempty(names)
                        columnNames = names;
                    end
                catch
                    columnNames = {};
                end
            end

            % 第3行起：数据（tab分隔的浮点数）
            dataCell = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line) || isempty(strtrim(line))
                    continue;
                end
                line = strrep(line, sprintf('\r'), '');
                parts = str2double(strsplit(line, '\t'));
                if ~all(isnan(parts))
                    dataCell{end+1} = parts; %#ok<AGROW>
                end
            end

            if isempty(dataCell)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'FDOT text: no data rows');
            end

            % 对齐列数
            nCols = max(cellfun(@length, dataCell));
            data = NaN(length(dataCell), nCols);
            for i = 1:length(dataCell)
                row = dataCell{i};
                data(i, 1:length(row)) = row;
            end

            formatTag = 'fdot_text';
        end

        function [data, columnNames, formatTag] = ParseSwppText(filePath)
        % ParseSwppText SWPP 文本格式：10行头 + 空格分隔数据

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 读取头部
            headerLines = cell(10, 1);
            for i = 1:10
                headerLines{i} = fgetl(fid);
                if ~ischar(headerLines{i})
                    error('SignalAnalysis:DataReaderFactory:ParseFailed', 'SWPP header too short');
                end
            end

            columnNames = {};

            % 读取数据
            dataCell = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line) || isempty(strtrim(line))
                    continue;
                end
                parts = str2double(strsplit(strtrim(line)));
                if all(isnan(parts))
                    continue;
                end
                dataCell{end+1} = parts; %#ok<AGROW>
            end

            if isempty(dataCell)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'SWPP no data rows');
            end

            % 对齐列数
            nCols = max(cellfun(@length, dataCell));
            data = NaN(length(dataCell), nCols);
            for i = 1:length(dataCell)
                row = dataCell{i};
                data(i, 1:length(row)) = row;
            end

            formatTag = 'swpp_text';
        end

        function [data, columnNames, formatTag] = ParseAcsSwpp(filePath)
        % ParseAcsSwpp ACS SWPP 格式（step/variable 结构）

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 读取所有行
            allLines = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line)
                    allLines{end+1} = line; %#ok<AGROW>
                end
            end

            % 寻找数据起始行（第一个全是数值的行）
            dataStartIdx = 0;
            for i = 1:length(allLines)
                parts = str2double(strsplit(strtrim(allLines{i})));
                if ~all(isnan(parts)) && length(parts) > 1
                    dataStartIdx = i;
                    break;
                end
            end

            if dataStartIdx == 0
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'ACS SWPP no data found');
            end

            % 读取数据
            dataCell = {};
            for i = dataStartIdx:length(allLines)
                parts = str2double(strsplit(strtrim(allLines{i})));
                if ~all(isnan(parts)) && length(parts) > 1
                    dataCell{end+1} = parts; %#ok<AGROW>
                end
            end

            nCols = max(cellfun(@length, dataCell));
            data = NaN(length(dataCell), nCols);
            for i = 1:length(dataCell)
                row = dataCell{i};
                data(i, 1:length(row)) = row;
            end

            columnNames = {};
            formatTag = 'acs_swpp';
        end

        function [data, columnNames, formatTag] = ParseMultiSection(filePath)
        % ParseMultiSection 多段自定义格式

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 读取所有行
            allLines = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line)
                    allLines{end+1} = line; %#ok<AGROW>
                end
            end

            % 寻找数据起始行
            dataStartIdx = 0;
            for i = 1:length(allLines)
                parts = str2double(strsplit(strtrim(allLines{i})));
                if ~all(isnan(parts)) && length(parts) > 1
                    dataStartIdx = i;
                    break;
                end
            end

            if dataStartIdx == 0
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'MultiSection no data found');
            end

            dataCell = {};
            for i = dataStartIdx:length(allLines)
                parts = str2double(strsplit(strtrim(allLines{i})));
                if ~all(isnan(parts)) && length(parts) > 1
                    dataCell{end+1} = parts; %#ok<AGROW>
                end
            end

            nCols = max(cellfun(@length, dataCell));
            data = NaN(length(dataCell), nCols);
            for i = 1:length(dataCell)
                row = dataCell{i};
                data(i, 1:length(row)) = row;
            end

            columnNames = {};
            formatTag = 'multi_section';
        end

        function [data, columnNames, formatTag] = ParseItpsText(filePath)
        % ParseItpsText ITPS 文本格式

            data = load(filePath);
            if ~isnumeric(data) || ~ismatrix(data)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'ITPS text file does not contain a numeric matrix');
            end
            columnNames = {};
            formatTag = 'itps_text';
        end

        function [data, columnNames, formatTag] = ParseAcsCsv(filePath)
        % ParseAcsCsv ACS CSV 格式

            [data, columnNames, formatTag] = DataReaderFactory.ParseCsvFile(filePath);
        end

        function [data, columnNames, formatTag] = ParseFrfxFile(filePath)
        % ParseFrfxFile FRFX 传函格式：多段 freq/amp/phase 数据

            fieldList = {'Measure_Closed_Loop_Data'; ...
                         'Measure_Open_Loop_Data'; ...
                         'Measure_Controller_Data'; ...
                         'Measure_Plant_Data'; ...
                         'Design_Closed_Loop_Data'; ...
                         'Design_Open_Loop_Data'; ...
                         'Design_Controller_Data'; ...
                         'Design_Plant_Data'};

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            data = [];
            columnNames = {'Frequency', 'Amplitude', 'Phase'};

            while ~feof(fid)
                tline = fgetl(fid);
                if ~ischar(tline), break; end

                for jj = 1:length(fieldList)
                    if contains(tline, fieldList{jj})
                        % 跳过 Label 行
                        fgetl(fid);
                        fgetl(fid);

                        % 读取数据行直到 '];'
                        rows = {};
                        while true
                            tline = fgetl(fid);
                            if contains(tline, '];'), break; end
                            parts = textscan(tline, '%s', 'Delimiter', ',', ...
                                'MultipleDelimsAsOne', 1);
                            rows{end+1} = str2double(parts{1})'; %#ok<AGROW>
                        end

                        data = vertcat(rows{:});
                        formatTag = 'frfx';
                        return;
                    end
                end
            end

            if isempty(data)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'No data sections found in .frfx file');
            end
        end

        function ValidateStructure(data)
        % ValidateStructure 结构验证
        %
        % 验证规则：
        %   维度：rows >= 2, cols >= 1
        %   无全 NaN 列
        %   NaN 比例 < 50%
        %   无 Inf 值

            [nRows, nCols] = size(data);

            if nRows < 2 || nCols < 1
                error('SignalAnalysis:DataReaderFactory:ValidationFailed', ...
                    'Data dimensions too small: %d×%d', nRows, nCols);
            end

            % 检查全 NaN 列
            for c = 1:nCols
                if all(isnan(data(:, c)))
                    error('SignalAnalysis:DataReaderFactory:ValidationFailed', ...
                        'Column %d is all NaN', c);
                end
            end

            % 检查 NaN 比例
            nanRatio = sum(isnan(data(:))) / numel(data);
            if nanRatio > 0.5
                error('SignalAnalysis:DataReaderFactory:ValidationFailed', ...
                    'Too many NaN values: %.1f%%', nanRatio * 100);
            end

            % 检查 Inf
            if any(isinf(data(:)))
                error('SignalAnalysis:DataReaderFactory:ValidationFailed', ...
                    'Data contains Inf values');
            end
        end

        function score = ComputeConfidence(data)
        % ComputeConfidence 置信度评分（仅基于数据质量）
        %
        % 用于 .dat 格式探测时选择最佳解析器
        % 基础 50 分，根据特征加减

            score = 50;

            [nRows, nCols] = size(data);

            % 行数
            if nRows > 1000
                score = score + 10;
            end
            if nRows > 10000
                score = score + 10;
            end

            % 列数
            if nCols >= 2 && nCols <= 100
                score = score + 15;
            end

            % NaN 比例
            nanRatio = sum(isnan(data(:))) / numel(data);
            score = score - 30 * nanRatio;

            % 信号平滑性
            if nCols > 0 && nRows > 10
                diffs = diff(data(:, 1));
                if std(diffs) > 0
                    cv = std(diffs) / mean(abs(diffs));
                    if cv < 0.1
                        score = score + 15;
                    end
                end
            end

            score = max(0, min(100, score));
        end

        function simplified = SimplifyColumnName(rawName)
        % SimplifyColumnName 左右都去关键字，提取后面的部分拼接
        %
        % 有 => 时：左去关键字取末段 + 右去关键字，拼接
        %   'BLADE_AX_Y2=>CTRL_ERROR' → 'Y2_ERROR'
        %   'SN_ENC_Y2L=>SENSOR_INT_OUT' → 'Y2L_INT_OUT'
        %
        % 无 => 时：去掉开头关键字
        %   'CTRL_ERROR' → 'ERROR'
        %   'BLADE_AX_Y2' → 'BLADE_AX_Y2'（无关键字，保留原名）

            keywords = {'CTRL', 'SENSOR', 'POS', 'SN', 'AS', 'MS'};

            arrowIdx = strfind(rawName, '=>');
            if ~isempty(arrowIdx)
                % 有 =>：左去关键字取末段，右去关键字
                leftPart = rawName(1:arrowIdx(1)-1);
                rightPart = rawName(arrowIdx(1)+2:end);

                % 左边去关键字，取末段
                leftSuffix = DataReaderFactory.StripKeywordPrefix(leftPart, keywords);
                leftParts = strsplit(leftSuffix, '_');
                if ischar(leftParts), leftParts = {leftParts}; end
                leftSuffix = leftParts{end};

                % 右边去关键字
                rightSuffix = DataReaderFactory.StripKeywordPrefix(rightPart, keywords);

                simplified = [leftSuffix '_' rightSuffix];
            else
                % 无 =>：去开头关键字
                simplified = DataReaderFactory.StripKeywordPrefix(rawName, keywords);
            end

            if length(simplified) > 63
                simplified = simplified(1:63);
            end
        end

        function result = StripKeywordPrefix(name, keywords)
        % StripKeywordPrefix 去掉名称开头的关键字前缀
        %
        % 'CTRL_ERROR' → 'ERROR'
        % 'SENSOR_INT_OUT' → 'INT_OUT'
        % 'BLADE_AX_Y2' → 'BLADE_AX_Y2'

            parts = strsplit(name, '_');
            if ischar(parts), parts = {parts}; end

            if ~isempty(parts)
                first = upper(strtrim(parts{1}));
                isKeyword = any(cellfun(@(kw) strcmp(first, kw), keywords));
                if isKeyword && length(parts) > 1
                    result = strjoin(parts(2:end), '_');
                else
                    result = name;
                end
            else
                result = name;
            end
        end

        function names = DeduplicateNames(names)
        % DeduplicateNames 对重复名称加后缀 _2, _3 ...
        %
        % {'CTRL', 'CTRL', 'SENSOR'} → {'CTRL', 'CTRL_2', 'SENSOR'}

            seen = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for i = 1:length(names)
                name = names{i};
                if isKey(seen, name)
                    count = seen(name) + 1;
                    seen(name) = count;
                    names{i} = sprintf('%s_%d', name, count);
                else
                    seen(name) = 1;
                end
            end
        end

        function WriteJson(jsonPath, data)
        % WriteJson 将 struct 写入 JSON 文件

            try
                jsonText = jsonencode(data, 'PrettyPrint', true);
            catch
                jsonText = jsonencode(data);
            end

            fid = fopen(jsonPath, 'w');
            if fid < 0
                warning('SignalAnalysis:DataReaderFactory:JsonWriteFailed', ...
                    'Cannot write JSON file: %s', jsonPath);
                return;
            end
            fprintf(fid, '%s', jsonText);
            fclose(fid);
        end
    end
end
