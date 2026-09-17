classdef DataReaderFactory
% DataReaderFactory - 数据读取工厂
%
% 两步设计：
%   Step 1: ReadDataMatrix → 解析文件，返回 [data, rawNames, formatTag]
%   Step 2: MatchColumnNames → 列名与数据列对齐（纯函数）
%
% 两种导入模式：
%   ImportFiles(filePaths, outputDir) → 统一导入入口
%   ImportToStandard(filePath, outputDir) → 单文件导入（含缓存）
%
% 设计原则：
%   - ReadDataMatrix 负责所有列名提取（含兜底），返回可信 rawNames
%   - MatchColumnNames 是纯函数，不访问文件系统
%   - 采样率、单位、描述由用户在 UI 界面提供

    methods (Static)
        % ---- 用户可配置：列名简化规则 ----
        % 用法：
        %   DataReaderFactory.SetKeywords({'CTRL','SENSOR','MYKEY'});
        %   DataReaderFactory.SetSeparators({'=>' , '_+_', '->'});
        %   DataReaderFactory.ResetSimplifyRules();  % 恢复默认

        function SetKeywords(kw)
        % SetKeywords 设置列名简化关键字列表
            if ~iscell(kw) || isempty(kw)
                error('Keywords must be a non-empty cell array of strings');
            end
            DataReaderFactory.simplifyStorage('set', 'keywords', kw);
        end

        function kw = GetKeywords()
        % GetKeywords 获取当前关键字列表
            kw = DataReaderFactory.simplifyStorage('get', 'keywords');
        end

        function SetSeparators(seps)
        % SetSeparators 设置列名简化分隔符列表（按优先级排列）
            if ~iscell(seps) || isempty(seps)
                error('Separators must be a non-empty cell array of strings');
            end
            DataReaderFactory.simplifyStorage('set', 'separators', seps);
        end

        function seps = GetSeparators()
        % GetSeparators 获取当前分隔符列表
            seps = DataReaderFactory.simplifyStorage('get', 'separators');
        end

        function prefixes = GetVendorPrefixes()
        % GetVendorPrefixes 获取厂商前缀列表（可配置）
            prefixes = DataReaderFactory.simplifyStorage('get', 'vendorPrefixes');
        end

        function SetVendorPrefixes(prefixes)
        % SetVendorPrefixes 设置厂商前缀列表
            if ~iscell(prefixes)
                error('VendorPrefixes must be a cell array of strings');
            end
            DataReaderFactory.simplifyStorage('set', 'vendorPrefixes', prefixes);
        end

        function ResetSimplifyRules()
        % ResetSimplifyRules 恢复默认关键字、分隔符和厂商前缀
            DataReaderFactory.simplifyStorage('set', 'keywords', ...
                {'CTRL', 'SENSOR', 'POS', 'SN', 'AS', 'MS', 'CTRLVAR'});
            DataReaderFactory.simplifyStorage('set', 'separators', ...
                {'=>' , '_+_'});
            DataReaderFactory.simplifyStorage('set', 'vendorPrefixes', ...
                {'VM4A_', 'DSA_', 'FRF_'});
        end

        function path = GetConfigPath()
        % GetConfigPath 返回 simplify_rules.json 的路径（与 DataReaderFactory.m 同目录）
            thisDir = fileparts(mfilename('fullpath'));
            path = fullfile(thisDir, 'simplify_rules.json');
        end

        function SaveConfig()
        % SaveConfig 将当前规则保存到 simplify_rules.json
            cfg.keywords  = DataReaderFactory.GetKeywords();
            cfg.separators = DataReaderFactory.GetSeparators();
            cfg.vendorPrefixes = DataReaderFactory.GetVendorPrefixes();
            jsonPath = DataReaderFactory.GetConfigPath();
            DataReaderFactory.WriteJson(jsonPath, cfg);
            fprintf('[DataReaderFactory] 配置已保存: %s\n', jsonPath);
        end

        function tf = LoadConfig()
        % LoadConfig 从 simplify_rules.json 加载规则
        % 返回 true 表示加载成功，false 表示文件不存在或格式错误
            jsonPath = DataReaderFactory.GetConfigPath();
            tf = false;
            if ~isfile(jsonPath)
                return;
            end
            try
                txt = fileread(jsonPath);
                cfg = jsondecode(txt);
                if isfield(cfg, 'keywords') && isfield(cfg, 'separators')
                    DataReaderFactory.SetKeywords(cfg.keywords);
                    DataReaderFactory.SetSeparators(cfg.separators);
                    tf = true;
                end
                if isfield(cfg, 'vendorPrefixes')
                    DataReaderFactory.SetVendorPrefixes(cfg.vendorPrefixes);
                end
            catch ME
                warning('DataReaderFactory:ConfigLoadFailed', ...
                    '配置文件读取失败: %s', ME.message);
            end
        end

        function CreateDefaultConfig()
        % CreateDefaultConfig 创建默认配置文件（如已存在则跳过）
            jsonPath = DataReaderFactory.GetConfigPath();
            if isfile(jsonPath)
                fprintf('[DataReaderFactory] 配置文件已存在: %s\n', jsonPath);
                return;
            end
            DataReaderFactory.ResetSimplifyRules();
            DataReaderFactory.SaveConfig();
        end
    end

    methods (Static, Access = private)
        function varargout = simplifyStorage(action, key, value)
        % simplifyStorage 统一持久化存储（单一 persistent 变量）
            persistent rules
            if isempty(rules)
                rules = DataReaderFactory.loadOrDefault();
            end
            switch action
                case 'get'
                    varargout{1} = rules.(key);
                case 'set'
                    rules.(key) = value;
            end
        end

        function rules = loadOrDefault()
        % loadOrDefault 优先从文件加载，失败则用默认值
            rules.keywords  = {'CTRL', 'SENSOR', 'POS', 'SN', 'AS', 'MS', 'CTRLVAR'};
            rules.separators = {'=>' , '_+_'};
            rules.vendorPrefixes = {'VM4A_', 'DSA_', 'FRF_'};
            try
                jsonPath = DataReaderFactory.GetConfigPath();
                if isfile(jsonPath)
                    txt = fileread(jsonPath);
                    cfg = jsondecode(txt);
                    if isfield(cfg, 'keywords') && isfield(cfg, 'separators')
                        rules.keywords  = cfg.keywords;
                        rules.separators = cfg.separators;
                    end
                    if isfield(cfg, 'vendorPrefixes')
                        rules.vendorPrefixes = cfg.vendorPrefixes;
                    end
                end
            catch ME
                warning('DataReaderFactory:ConfigLoadFailed', ...
                    '配置文件解析失败，使用默认规则: %s', ME.message);
            end
        end
    end

    methods (Static)
        function [data, rawNames, formatTag] = ReadDataMatrix(filePath)
        % ReadDataMatrix 解析文件，返回数据矩阵、原始列名、格式标签
        % 职责：所有列名提取策略（含兜底）在此完成，返回的 rawNames 可信

            [~, ~, ext] = fileparts(filePath);
            ext = lower(ext);

            switch ext
                case '.dat'
                    [data, rawNames, formatTag] = DataReaderFactory.ParseDatFile(filePath);
                case '.txt'
                    [data, rawNames, formatTag] = DataReaderFactory.ParseTxtFile(filePath);
                case '.csv'
                    [data, rawNames, formatTag] = DataReaderFactory.ParseCsvFile(filePath);
                case '.mat'
                    [data, rawNames, formatTag] = DataReaderFactory.ParseMatFile(filePath);
                case {'.xlsx', '.xls'}
                    [data, rawNames, formatTag] = DataReaderFactory.ParseExcelFile(filePath);
                case ''
                    [data, rawNames, formatTag] = DataReaderFactory.ParseDatFile(filePath);
                otherwise
                    error('SignalAnalysis:DataReaderFactory:UnsupportedFormat', ...
                        'Unsupported file format: %s', ext);
            end

            if isempty(rawNames), rawNames = {}; end
            DataReaderFactory.ValidateStructure(data);

            % 兜底：rawNames 为空时，尝试 ExtractHeaderColumnNames
            if isempty(rawNames) || all(cellfun(@isempty, rawNames))
                rawNames = DataReaderFactory.ExtractHeaderColumnNames(filePath, size(data, 2));
            end
            % 无扩展名文件：trace 头元数据覆盖
            if isempty(ext)
                traceNames = DataReaderFactory.ExtractTraceColumnName(filePath);
                if ~isempty(traceNames)
                    rawNames = traceNames;
                end
            end
        end

        function [columnNames, data] = MatchColumnNames(rawNames, data)
        % MatchColumnNames 列名与数据列对齐（纯函数）
        %
        % 输入：
        %   rawNames - cell 来自 ReadDataMatrix 的原始列名（已含兜底）
        %   data     - 数据矩阵
        %
        % 逻辑：
        %   1. 检测首列是否为 time/index，若是则命名并从匹配池排除
        %   2. 简化列名（关键字 + 去重）
        %   3. 匹配：列名数 <= 剩余数据列数 → 使用，不足补默认名
        %            列名数 > 剩余数据列数 → 截断

            [nRows, nCols] = size(data);

            % --- Step 1: 检测首列 time/index ---
            firstColIsIndex = false;
            if nCols >= 2 && nRows >= 3
                firstCol = data(:, 1);
                diffs = diff(firstCol);
                % 整数索引检测
                if all(diffs > 0) && all(abs(diffs - round(diffs)) < 1e-9) ...
                        && all(abs(firstCol - round(firstCol)) < 1e-9)
                    firstColIsIndex = true;
                end
                % 等间隔时间轴检测
                if ~firstColIsIndex && all(diffs > 0)
                    stepStd = std(diffs);
                    stepMean = mean(diffs);
                    if stepMean > 0 && stepStd / stepMean < 1e-6
                        firstColIsIndex = true;
                    end
                end
            end

            if firstColIsIndex
                indexName = 'index';
                dataCols = nCols - 1;
            else
                indexName = '';
                dataCols = nCols;
            end

            % --- Step 2: 简化列名 ---
            names = rawNames;
            if ~isempty(names) && iscell(names)
                for i = 1:length(names)
                    if ~isempty(names{i})
                        names{i} = DataReaderFactory.CleanRawName(names{i});
                    end
                end
                names = DataReaderFactory.DeduplicateNames(names, true);
            end

            % --- Step 3: 匹配 ---
            nNames = length(names);

            if nNames == 0
                dataNames = arrayfun(@(i) sprintf('Channel_%d', i), 1:dataCols, 'UniformOutput', false);
            elseif nNames <= dataCols
                dataNames = names;
                for i = nNames+1:dataCols
                    dataNames{i} = sprintf('Channel_%d', i);
                end
            else
                dataNames = names(1:dataCols);
            end

            % 组装最终列名
            if firstColIsIndex
                columnNames = [{indexName}, dataNames];
            else
                columnNames = dataNames;
            end
        end

        function UpdateColumnNamesInMeta(matPath, colNames)
        % UpdateColumnNamesInMeta 更新 _meta.json 中的列名
        % 输入：matPath 为 _standardized.mat 的完整路径
            [outDir, baseName] = fileparts(matPath);
            metaPath = fullfile(outDir, [baseName '_meta.json']);
            if ~exist(metaPath, 'file')
                return;
            end

            meta = jsondecode(fileread(metaPath));
            nCols = length(colNames);
            for i = 1:nCols
                if i <= length(meta.columns)
                    meta.columns(i).name = colNames{i};
                end
            end
            DataReaderFactory.WriteJson(metaPath, meta);
        end

        function dataset = LoadStandard(matPath)
        % LoadStandard 阶段二：标准化 .mat → Dataset
        %
        % 加载 .mat（纯数据）+ _meta.json（全部元数据），构造 Dataset

            loaded = load(matPath);
            if ~isfield(loaded, 'data')
                error('SignalAnalysis:DataReaderFactory:InvalidCache', ...
                    'Missing data in %s — not a valid cache file', matPath);
            end
            data = loaded.data;

            % 从 _meta.json 读取全部元数据
            metadata = struct();
            [~, baseName] = fileparts(matPath);
            jsonPath = fullfile(fileparts(matPath), [baseName '_meta.json']);
            if ~exist(jsonPath, 'file')
                error('SignalAnalysis:DataReaderFactory:MissingMeta', ...
                    'Missing _meta.json for %s', matPath);
            end

            meta = jsondecode(fileread(jsonPath));
            metadata.json = meta;

            sourcePath = '';
            if isfield(meta, 'source_file'), sourcePath = meta.source_file; end
            formatTag = '';
            if isfield(meta, 'source_format'), formatTag = meta.source_format; end
            sampleRate = [];
            if isfield(meta, 'sample_rate') && ~isempty(meta.sample_rate)
                sampleRate = meta.sample_rate;
            end

            nCols = size(data, 2);
            columnNames = cell(1, nCols);
            units = cell(1, nCols);
            descriptions = cell(1, nCols);
            if isfield(meta, 'columns') && isstruct(meta.columns)
                for c = 1:min(numel(meta.columns), nCols)
                    if isfield(meta.columns(c), 'name')
                        columnNames{c} = meta.columns(c).name;
                    end
                    if isfield(meta.columns(c), 'unit')
                        units{c} = meta.columns(c).unit;
                    end
                    if isfield(meta.columns(c), 'description')
                        descriptions{c} = meta.columns(c).description;
                    end
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
            data = loaded.data;

            % 从 _meta.json 读列名
            columnNames = {};
            [~, baseName] = fileparts(matPath);
            metaPath = fullfile(fileparts(matPath), [baseName '_meta.json']);
            if exist(metaPath, 'file')
                try
                    meta = jsondecode(fileread(metaPath));
                    if isfield(meta, 'columns') && isstruct(meta.columns)
                        columnNames = cell(1, numel(meta.columns));
                        for i = 1:numel(meta.columns)
                            columnNames{i} = meta.columns(i).name;
                        end
                    end
                catch ME
                    warning('DataReaderFactory:MetaParseFailed', ...
                        '元数据解析失败 %s: %s', metaPath, ME.message);
                end
            end

            nCols = size(data, 2);

            % 补齐列名到 nCols
            if length(columnNames) < nCols
                columnNames(end+1:nCols) = {''};
            end

            % 构建写入矩阵：1行列名 + N行数据
            allData = [columnNames(1:nCols); num2cell(data)];

            if exist('writecell', 'file')
                writecell(allData, xlsxPath);
            else
                xlswrite(xlsxPath, allData);
            end
        end

        function curves = ExtractFrfCurves(dataset)
        % ExtractFrfCurves 从 FRF 数据集提取频响曲线
        %
        % 输入：
        %   dataset - Dataset 对象。
        %     4 列        → 单曲线，列角色固定 [amp, phase, corr, freq]
        %     4K 列       → 每 4 列一组切 K 条曲线（dsa_frf 多曲线文件）
        %     3K+1 列     → 第 1 列为共享 Freq，其余每 3 列 [amp, phase, corr]
        % 输出：
        %   curves - struct array：name/freq/amp/phase/corr（均为 [N×1] double）

            nCols = dataset.ColumnCount;
            [~, baseName] = fileparts(dataset.SourcePath);
            baseName = strrep(baseName, '_standardized', '');

            if nCols == 4
                curves = struct();
                curves.name = baseName;
                curves.freq = dataset.GetColumn(4);
                curves.amp = dataset.GetColumn(1);
                curves.phase = dataset.GetColumn(2);
                curves.corr = dataset.GetColumn(3);
                return;
            end

            if mod(nCols, 4) == 0
                k = nCols / 4;
                curves = struct('name', {}, 'freq', {}, 'amp', {}, 'phase', {}, 'corr', {});
                for i = 1:k
                    base = (i - 1) * 4;
                    curves(i).name = sprintf('%s#%d', baseName, i);
                    curves(i).freq = dataset.GetColumn(base + 4);
                    curves(i).amp = dataset.GetColumn(base + 1);
                    curves(i).phase = dataset.GetColumn(base + 2);
                    curves(i).corr = dataset.GetColumn(base + 3);
                end
            elseif mod(nCols - 1, 3) == 0 && nCols > 4
                k = (nCols - 1) / 3;
                sharedFreq = dataset.GetColumn(1);
                curves = struct('name', {}, 'freq', {}, 'amp', {}, 'phase', {}, 'corr', {});
                for i = 1:k
                    base = 1 + (i - 1) * 3;
                    curves(i).name = sprintf('%s#%d', baseName, i);
                    curves(i).freq = sharedFreq;
                    curves(i).amp = dataset.GetColumn(base + 1);
                    curves(i).phase = dataset.GetColumn(base + 2);
                    curves(i).corr = dataset.GetColumn(base + 3);
                end
            else
                error('SignalAnalysis:DataReaderFactory:InvalidFrfLayout', ...
                    '无法识别 FRF 列布局: %d 列', nCols);
            end
        end

        function tf = IsGeneratedFile(filePath)
        % IsGeneratedFile 判断是否为工具生成文件
        %
        % .mat 文件：检查同目录是否存在 companion _meta.json（而非文件名模式）
        %   避免误杀用户创建的 *_standardized.mat
        % 其他文件：按文件名后缀匹配
            [~, name, ext] = fileparts(filePath);
            if strcmpi(ext, '.mat')
                metaPath = fullfile(fileparts(filePath), [name '_meta.json']);
                tf = exist(metaPath, 'file') > 0;
            else
                tf = strcmpi(ext, '.json') && endsWith(name, '_meta', 'IgnoreCase', true) ...
                  || strcmpi(ext, '.xlsx') && endsWith(name, '_review', 'IgnoreCase', true);
            end
        end

        function [files, warnings] = DiscoverDirectory(dirPath, extensions)
        % DiscoverDirectory 递归扫描目录，返回所有源数据文件（扁平列表）
            files = {};
            warnings = {};
            listing = dir(dirPath);
            for i = 1:length(listing)
                if listing(i).isdir
                    if strcmp(listing(i).name, '.') || strcmp(listing(i).name, '..')
                        continue;
                    end
                    subDir = fullfile(dirPath, listing(i).name);
                    [subFiles, subWarnings] = DataReaderFactory.DiscoverDirectory(subDir, extensions);
                    files = [files, subFiles]; %#ok<AGROW>
                    warnings = [warnings, subWarnings]; %#ok<AGROW>
                else
                    if startsWith(listing(i).name, '.')
                        continue;
                    end
                    fullPath = fullfile(dirPath, listing(i).name);
                    if DataReaderFactory.IsGeneratedFile(fullPath)
                        warnings{end+1} = sprintf('跳过生成文件: %s', listing(i).name); %#ok<AGROW>
                        continue;
                    end
                    [~, fname, ext] = fileparts(listing(i).name);
                    if isempty(ext)
                        if listing(i).bytes == 0, continue; end
                    elseif ~any(strcmpi(ext, extensions))
                        continue;
                    end
                    files{end+1} = struct('path', fullPath, 'fname', fname); %#ok<AGROW>
                end
            end
        end

        function dirGroups = GroupByDirectory(files)
        % GroupByDirectory 按所在目录分组
            dirGroups = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:length(files)
                [dirPath, ~] = fileparts(files{i}.path);
                if dirGroups.isKey(dirPath)
                    dirGroups(dirPath) = [dirGroups(dirPath), {files{i}}];
                else
                    dirGroups(dirPath) = {files{i}};
                end
            end
        end

        function [cached, isStale, stalePaths] = CheckDirCache(dirPath, sourceFiles)
        % CheckDirCache 目录级缓存检查（基于数据 hash 判定）
        %
        % 验证逻辑：
        %   1. 读 _meta.json 的 source_file 验证缓存对应当前源文件
        %   2. 快速预检（源文件 bytes+datenum）→ 无变化直接用缓存
        %   3. 预检不通过 → 解析源文件，计算数据 hash，与 data_hash 比对
        %
        % isStale 触发条件（任一满足）：
        %   - 有源文件不在缓存覆盖范围内
        %   - 有源文件的数据 hash 与缓存不同
        %
        % 输出：
        %   cached     - 匹配当前源文件的缓存结果 cell 数组
        %   isStale    - true 表示需重新处理（cached 此时为空）
        %   stalePaths - isStale=true 时，需清理的旧缓存 .mat 文件路径

            cached = {};
            isStale = false;
            stalePaths = {};

            mats = dir(fullfile(dirPath, '*_standardized.mat'));
            if isempty(mats), return; end

            % 构建当前源文件集合
            srcPaths = cellfun(@(f) f.path, sourceFiles, 'UniformOutput', false);
            srcSet = containers.Map(srcPaths, ones(1, length(srcPaths)));
            coveredSrc = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            for s = 1:length(srcPaths)
                coveredSrc(srcPaths{s}) = false;
            end

            % 按 source_file 分组，每个源文件只保留最新缓存
            sourceToMat = containers.Map('KeyType', 'char', 'ValueType', 'any');
            cacheHashes = containers.Map('KeyType', 'char', 'ValueType', 'any');
            cacheStats = containers.Map('KeyType', 'char', 'ValueType', 'any');

            for k = 1:length(mats)
                matPath = fullfile(dirPath, mats(k).name);
                jsonPath = strrep(matPath, '.mat', '_meta.json');
                if ~isfile(jsonPath), continue; end

                try
                    meta = jsondecode(fileread(jsonPath));
                    if ~isfield(meta, 'source_file'), continue; end
                catch ME
                    warning('DataReaderFactory:MetaScanFailed', ...
                        '元数据扫描跳过 %s: %s', jsonPath, ME.message);
                    continue;
                end

                srcFile = meta.source_file;
                if isempty(srcFile), continue; end

                % 拆分分号拼接路径（合并文件场景）
                parts = strsplit(srcFile, ';');
                parts = strtrim(parts);
                parts = parts(~cellfun('isempty', parts));
                if isempty(parts), continue; end

                % 检查是否所有源文件都在当前集合中
                allMatch = true;
                for p = 1:length(parts)
                    if ~srcSet.isKey(parts{p})
                        allMatch = false;
                        break;
                    end
                end
                if ~allMatch, continue; end

                % 标记源文件已被缓存覆盖
                for p = 1:length(parts)
                    coveredSrc(parts{p}) = true;
                end

                % 合并文件用完整 srcFile 作 key，单文件用 parts{1}
                if length(parts) > 1
                    cacheKey = srcFile;
                else
                    cacheKey = parts{1};
                end

                % 同一 key 有多个缓存 → 保留最新的
                if sourceToMat.isKey(cacheKey)
                    existing = sourceToMat(cacheKey);
                    if mats(k).datenum > existing.datenum
                        sourceToMat(cacheKey) = mats(k);
                    end
                else
                    sourceToMat(cacheKey) = mats(k);
                end

                % 存储缓存 hash 和源文件 stat
                if isfield(meta, 'data_hash')
                    cacheHashes(cacheKey) = meta.data_hash;
                end
                if isfield(meta, 'source_stats')
                    cacheStats(cacheKey) = meta.source_stats;
                end
            end

            if sourceToMat.Count == 0, return; end

            % 检查 1：是否有源文件未被缓存覆盖 → stale
            coveredKeys = keys(coveredSrc);
            for k = 1:length(coveredKeys)
                if ~coveredSrc(coveredKeys{k})
                    isStale = true;
                    stalePaths = DataReaderFactory.CollectStalePaths(sourceToMat, dirPath);
                    return;
                end
            end

            % 检查 2：数据 hash 比对（快速预检 → 按需解析）
            % 构建 sourceFile → cacheKey 映射
            srcToCacheKey = containers.Map('KeyType', 'char', 'ValueType', 'char');
            srcKeys = keys(sourceToMat);
            for i = 1:length(srcKeys)
                parts = strsplit(srcKeys{i}, ';');
                parts = strtrim(parts);
                for p = 1:length(parts)
                    srcToCacheKey(parts{p}) = srcKeys{i};
                end
            end

            % 收集需要深度检查的源文件（预检不通过）
            needDeepCheck = {};
            for k = 1:length(sourceFiles)
                srcPath = sourceFiles{k}.path;
                if ~srcToCacheKey.isKey(srcPath), continue; end
                cacheKey = srcToCacheKey(srcPath);

                % 快速预检：当前源文件 stat vs 缓存时记录的源文件 stat
                srcInfo = dir(srcPath);
                if cacheStats.isKey(cacheKey)
                    storedStats = cacheStats(cacheKey);
                    matched = false;
                    for ss = 1:length(storedStats)
                        if strcmp(storedStats(ss).path, srcPath) ...
                                && srcInfo.bytes == storedStats(ss).bytes ...
                                && srcInfo.datenum == storedStats(ss).datenum
                            matched = true;
                            break;
                        end
                    end
                    if matched
                        continue;
                    end
                end

                % 预检不通过，加入深度检查列表
                needDeepCheck{end+1} = struct('path', srcPath, 'cacheKey', cacheKey); %#ok<AGROW>
            end

            % 深度检查：解析数据，计算 hash，比对
            for k = 1:length(needDeepCheck)
                item = needDeepCheck{k};
                if ~cacheHashes.isKey(item.cacheKey)
                    isStale = true;
                    stalePaths = DataReaderFactory.CollectStalePaths(sourceToMat, dirPath);
                    return;
                end

                try
                    [data, ~, ~] = DataReaderFactory.ReadDataMatrix(item.path);
                    currentHash = DataReaderFactory.ComputeDataHash(data);
                catch
                    isStale = true;
                    stalePaths = DataReaderFactory.CollectStalePaths(sourceToMat, dirPath);
                    return;
                end

                if ~strcmp(currentHash, cacheHashes(item.cacheKey))
                    isStale = true;
                    stalePaths = DataReaderFactory.CollectStalePaths(sourceToMat, dirPath);
                    return;
                end
            end

            % 构造返回结果
            resultKeys = keys(sourceToMat);
            for i = 1:length(resultKeys)
                matInfo = sourceToMat(resultKeys{i});
                matPath = fullfile(dirPath, matInfo.name);
                [~, name] = fileparts(matInfo.name);
                name = strrep(name, '_standardized', '');

                srcKey = resultKeys{i};
                parts = strsplit(srcKey, ';');
                parts = strtrim(parts);
                isMerged = length(parts) > 1;

                cached{end+1} = struct('name', name, 'matPath', matPath, ...
                    'isMerged', isMerged, 'sourcePaths', {parts}); %#ok<AGROW>
            end
        end

        function parsed = ParseAll(fileStructs)
        % ParseAll 解析多个文件，返回 parsed 结构体 cell 数组（纯解析，不做分组/合并/命名）
            parsed = {};
            for i = 1:length(fileStructs)
                try
                    [data, rawNames, formatTag] = DataReaderFactory.ReadDataMatrix(fileStructs{i}.path);
                    parsed{end+1} = struct( ...
                        'path', fileStructs{i}.path, ...
                        'data', data, ...
                        'rawNames', {rawNames}, ...
                        'formatTag', formatTag, ...
                        'fname', fileStructs{i}.fname, ...
                        'nCols', size(data, 2), ...
                        'nRows', size(data, 1)); %#ok<AGROW>
                catch e
                    warning('SignalAnalysis:Import', '文件 %s 解析失败: %s', ...
                        fileStructs{i}.fname, e.message);
                end
            end
        end

        function results = ProcessFileGroup(files, outputDir, rootDir)
        % ProcessFileGroup 处理同一目录下的文件组：解析 → 分组 → 合并/独立 → 保存
        % rootDir（可选）：导入根目录，用于构建层次化数据集名
            if nargin < 3, rootDir = ''; end
            results = {};
            parsed = DataReaderFactory.ParseAll(files);
            if isempty(parsed), return; end

            colCounts = cellfun(@(p) p.nCols, parsed);
            singleMask = colCounts == 1;
            singleParsed = parsed(singleMask);
            multiParsed = parsed(~singleMask);

            % 单通道处理
            if ~isempty(singleParsed)
                if length(singleParsed) > 1
                    [merged, colNames] = DataReaderFactory.MergeParsed(singleParsed);
                    srcPaths = cellfun(@(p) p.path, singleParsed, 'UniformOutput', false);
                    sourcePath = strjoin(srcPaths, ';');
                    mergeName = DataReaderFactory.GetDirectoryName(srcPaths{1}, rootDir);
                    matPath = DataReaderFactory.SaveStandard(merged, colNames, outputDir, ...
                        mergeName, sourcePath, 'merged');
                    results{end+1} = struct('name', mergeName, 'matPath', matPath, ...
                        'isMerged', true, 'sourcePaths', {srcPaths});
                else
                    item = singleParsed{1};
                    [colNames, cleanData] = DataReaderFactory.MatchColumnNames(...
                        item.rawNames, item.data);
                    singleName = DataReaderFactory.GetDirectoryName(item.path, rootDir);
                    matPath = DataReaderFactory.SaveStandard(cleanData, colNames, outputDir, ...
                        singleName, item.path, item.formatTag);
                    results{end+1} = struct('name', singleName, 'matPath', matPath, ...
                        'isMerged', false, 'sourcePaths', {{item.path}});
                end
            end

            % 多通道处理（各自独立，名称追加文件基名避免同目录多文件互相覆盖）
            for i = 1:length(multiParsed)
                item = multiParsed{i};
                [colNames, cleanData] = DataReaderFactory.MatchColumnNames(...
                    item.rawNames, item.data);
                multiName = sprintf('%s_%s', ...
                    DataReaderFactory.GetDirectoryName(item.path, rootDir), item.fname);
                matPath = DataReaderFactory.SaveStandard(cleanData, colNames, outputDir, ...
                    multiName, item.path, item.formatTag);
                results{end+1} = struct('name', multiName, 'matPath', matPath, ...
                    'isMerged', false, 'sourcePaths', {{item.path}});
            end
        end

        function [results, allWarnings] = Import(rootDir, varargin)
        % Import 统一入口：给定任意目录，返回所有数据集
            extensions = {'.dat', '.csv', '.txt', '.xlsx', '.mat'};
            results = {};
            allWarnings = {};

            [discovered, discWarnings] = DataReaderFactory.DiscoverDirectory(rootDir, extensions);
            allWarnings = [allWarnings, discWarnings];

            if isempty(discovered)
                fprintf('[DataReaderFactory] 未找到可导入的数据: %s\n', rootDir);
                return;
            end

            dirGroups = DataReaderFactory.GroupByDirectory(discovered);
            dirKeys = keys(dirGroups);
            for i = 1:length(dirKeys)
                dirPath = dirKeys{i};
                dirFiles = dirGroups(dirPath);

                [cached, isStale, stalePaths] = DataReaderFactory.CheckDirCache(dirPath, dirFiles);
                if ~isempty(cached) && ~isStale
                    results = [results, cached]; %#ok<AGROW>
                    continue;
                end

                % 清理旧缓存（isStale=true 时）
                if ~isempty(stalePaths)
                    for s = 1:length(stalePaths)
                        if isfile(stalePaths{s})
                            delete(stalePaths{s});
                        end
                        jsonP = strrep(stalePaths{s}, '.mat', '_meta.json');
                        if isfile(jsonP), delete(jsonP); end
                        xlsxP = strrep(stalePaths{s}, '.mat', '_review.xlsx');
                        if isfile(xlsxP), delete(xlsxP); end
                    end
                end

                dirResults = DataReaderFactory.ProcessFileGroup(dirFiles, dirPath, rootDir);
                results = [results, dirResults]; %#ok<AGROW>
            end

            results = DataReaderFactory.DeduplicateResults(results);

            if ~isempty(allWarnings)
                warning('SignalAnalysis:Import', '导入过程中有 %d 条提示', length(allWarnings));
            end
        end

        function dirName = GetDirectoryName(filePath, rootDir)
        % GetDirectoryName 从文件路径提取目录名
        % 无 rootDir：返回父目录名（向后兼容）
        % 有 rootDir：返回相对于 rootDir 的子路径（用 _ 连接）
        %   例：rootDir='Trace_data', filePath在 'Trace_data/20260310_161313/'
        %   → '20260310_161313'
            [dirPath, ~] = fileparts(filePath);
            if nargin >= 2 && ~isempty(rootDir)
                % 规范化路径（去掉末尾分隔符）
                rootNorm = strtrim(rootDir);
                if endsWith(rootNorm, filesep)
                    rootNorm = rootNorm(1:end-1);
                end
                dirNorm = strtrim(dirPath);
                if startsWith(dirNorm, rootNorm, 'IgnoreCase', ispc)
                    relPath = dirPath(length(rootNorm)+1:end);
                    relPath = strrep(relPath, filesep, '_');
                    relPath = strrep(relPath, '/', '_');
                    relPath = regexprep(relPath, '^_+', '');
                    if ~isempty(relPath)
                        dirName = relPath;
                        return;
                    end
                end
            end
            [~, dirName] = fileparts(dirPath);
        end

        function results = DeduplicateResults(results)
        % DeduplicateResults 按 matPath 去重（保留首次出现的）
            seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            unique = {};
            for i = 1:length(results)
                if ~seen.isKey(results{i}.matPath)
                    seen(results{i}.matPath) = true;
                    unique{end+1} = results{i}; %#ok<AGROW>
                end
            end
            results = unique;
        end

        function h = ComputeDataHash(data)
        % ComputeDataHash 计算数据矩阵的内容哈希（SHA-256 hex 字符串）
            bytes = typecast(data(:), 'uint8');
            try
                md = java.security.MessageDigest.getInstance('SHA-256');
                md.update(bytes);
                hashBytes = md.digest();
                h = sprintf('%02x', typecast(hashBytes, 'uint8'));
            catch
                h = sprintf('%x', sum(bytes) + sum(typecast(size(data), 'uint8')));
            end
        end

        function stats = CollectSourceStats(sourcePath)
        % CollectSourceStats 收集源文件的 bytes 和 datenum
        % sourcePath 可以是分号拼接的多文件路径
            parts = strsplit(sourcePath, ';');
            parts = strtrim(parts);
            parts = parts(~cellfun('isempty', parts));
            stats = cell(1, length(parts));
            for i = 1:length(parts)
                info = dir(parts{i});
                if ~isempty(info)
                    stats{i} = struct('path', parts{i}, 'bytes', info.bytes, 'datenum', info.datenum);
                else
                    stats{i} = struct('path', parts{i}, 'bytes', 0, 'datenum', 0);
                end
            end
        end

        function stalePaths = CollectStalePaths(sourceToMat, dirPath)
        % CollectStalePaths 收集需要清理的旧缓存路径
            stalePaths = {};
            matKeys = keys(sourceToMat);
            for m = 1:length(matKeys)
                stalePaths{end+1} = fullfile(dirPath, sourceToMat(matKeys{m}).name); %#ok<AGROW>
            end
        end

        function UpdateSampleRateInMat(matPath, sampleRate)
        % UpdateSampleRateInMat 更新 _meta.json 中的采样率
            DataReaderFactory.UpdateMetaField(matPath, 'sample_rate', sampleRate);
        end

        function UpdateDatasetNameInMat(matPath, newName)
        % UpdateDatasetNameInMat 更新 _meta.json 中的 dataset_name
            DataReaderFactory.UpdateMetaField(matPath, 'dataset_name', newName);
        end

        function name = LoadDatasetName(matPath)
        % LoadDatasetName 从 _meta.json 读取 dataset_name，无则返回 ''

            name = '';
            [outDir, baseName] = fileparts(matPath);
            jsonPath = fullfile(outDir, [baseName '_meta.json']);
            if ~isfile(jsonPath), return; end
            try
                meta = jsondecode(fileread(jsonPath));
                if isfield(meta, 'dataset_name') && ~isempty(meta.dataset_name)
                    name = regexprep(strtrim(meta.dataset_name), '^[▼▶]\s*', '');
                end
            catch ME
                warning('DataReaderFactory:DatasetNameReadFailed', ...
                    '数据集名称读取失败 %s: %s', jsonPath, ME.message);
            end
        end

        function matPath = SaveStandard(data, colNames, outputDir, baseName, sourcePath, formatTag)
        % SaveStandard 保存标准化结果（.mat + _meta.json）
        % Excel 导出改为手动：DataReaderFactory.ExportToExcel
            if ~exist(outputDir, 'dir')
                mkdir(outputDir);
            end

            nCols = size(data, 2);

            % 确保 colNames 长度匹配
            if length(colNames) < nCols
                for i = length(colNames)+1:nCols
                    colNames{i} = sprintf('Channel_%d', i);
                end
            end

            % 保存 .mat（纯数据）
            matPath = fullfile(outputDir, [baseName '_standardized.mat']);
            save(matPath, 'data', '-v7');

            % 保存 _meta.json
            meta = struct();
            meta.source_file = sourcePath;
            meta.source_format = formatTag;
            meta.data_hash = DataReaderFactory.ComputeDataHash(data);
            meta.source_stats = DataReaderFactory.CollectSourceStats(sourcePath);
            meta.import_time = datestr(now, 'yyyy-mm-ddTHH:MM:SS');
            meta.row_count = size(data, 1);
            meta.column_count = nCols;
            meta.sample_rate = [];
            meta.dataset_name = '';
            meta.columns = DataReaderFactory.BuildColumnMeta(colNames, {}, {}, nCols);

            jsonPath = fullfile(outputDir, [baseName '_standardized_meta.json']);
            DataReaderFactory.WriteJson(jsonPath, meta);
        end
    end

    methods (Static, Access = private)
        function UpdateMetaField(matPath, fieldName, value)
        % UpdateMetaField 通用：读 _meta.json → 改指定字段 → 写回
            [outDir, baseName] = fileparts(matPath);
            jsonPath = fullfile(outDir, [baseName '_meta.json']);
            if exist(jsonPath, 'file')
                try
                    meta = jsondecode(fileread(jsonPath));
                    meta.(fieldName) = value;
                    DataReaderFactory.WriteJson(jsonPath, meta);
                catch ME
                    warning('DataReaderFactory:MetaUpdateFailed', ...
                        '元数据字段更新失败 %s.%s: %s', jsonPath, fieldName, ME.message);
                end
            end
        end

        function [merged, colNames] = MergeParsed(parsed)
        % MergeParsed 合并多个单通道矩阵为多通道矩阵
        % 单通道文件不需要 time/index 检测，直接取 rawNames 第一个非空名称
            paths = cellfun(@(p) p.path, parsed, 'UniformOutput', false);
            [~, sortIdx] = sort(paths);
            parsed = parsed(sortIdx);

            nRows = parsed{1}.nRows;
            valid = true(1, length(parsed));
            droppedFiles = {};
            for i = 1:length(parsed)
                if parsed{i}.nRows ~= nRows
                    valid(i) = false;
                    [~, droppedName] = fileparts(parsed{i}.path);
                    droppedFiles{end+1} = droppedName; %#ok<AGROW>
                end
            end
            if ~isempty(droppedFiles)
                warning('SignalAnalysis:DataReaderFactory:RowMismatch', ...
                    '跳过行数不匹配的文件 (%d行 vs %d行): %s', ...
                    nRows, parsed{find(~valid,1)}.nRows, strjoin(droppedFiles, ', '));
            end
            parsed = parsed(valid);
            if isempty(parsed)
                error('SignalAnalysis:DataReaderFactory:NoData', ...
                    '所有文件行数不匹配，无法合并');
            end

            nCols = length(parsed);
            merged = zeros(nRows, nCols);
            colNames = cell(1, nCols);
            for i = 1:nCols
                merged(:, i) = parsed{i}.data(:, 1);
                % 拼接所有非空 rawNames（如 {'Y1','CTRL_ERROR'} → 'Y1_CTRL_ERROR'）
                name = '';
                if ~isempty(parsed{i}.rawNames)
                    parts = {};
                    for j = 1:length(parsed{i}.rawNames)
                        if ~isempty(parsed{i}.rawNames{j})
                            parts{end+1} = parsed{i}.rawNames{j}; %#ok<AGROW>
                        end
                    end
                    if ~isempty(parts)
                        name = DataReaderFactory.CleanRawName(strjoin(parts, '_'));
                    end
                end
                if isempty(name)
                    [~, name] = fileparts(parsed{i}.path);
                end
                colNames{i} = name;
            end
            % 去重（合并后可能同名，如两个 'ERROR'）
            colNames = DataReaderFactory.DeduplicateNames(colNames, true);
        end

        function columns = BuildColumnMeta(colNames, units, descriptions, nCols)
        % BuildColumnMeta 构建列元数据结构体数组
            columns = cell(1, nCols);
            for c = 1:nCols
                col = struct();
                col.index = c;
                if ~isempty(colNames) && c <= length(colNames)
                    col.name = colNames{c};
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
            columns = [columns{:}];
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
                catch ME
                    warning('DataReaderFactory:ParserFailed', ...
                        '解析器跳过 %s: %s', filePath, ME.message);
                end
            end

            % 兜底：通用文本解析（跳过非数值行，提取列名）
            if bestScore < 0
                try
                    [d, n] = DataReaderFactory.ParseGenericText(filePath);
                    DataReaderFactory.ValidateStructure(d);
                    score = DataReaderFactory.ComputeConfidence(d);
                    if score > bestScore
                        bestScore = score;
                        bestData = d;
                        bestNames = n;
                        bestTag = 'generic_text';
                    end
                catch ME
                    warning('DataReaderFactory:GenericParseFailed', ...
                        '通用文本解析失败 %s: %s', filePath, ME.message);
                end
            end

            if bestScore < 0
                error('SignalAnalysis:DataReaderFactory:AllParsersFailed', ...
                    'Could not parse .dat file with any known format: %s', filePath);
            end

            data = bestData;
            columnNames = bestNames;
            formatTag = bestTag;
        end

        function [data, columnNames] = ParseGenericText(filePath)
        % ParseGenericText 通用文本解析：跳过非数值行提取列名，读取数值矩阵

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            columnNames = {};
            dataLines = {};
            headerCandidate = '';
            lineNum = 0;

            while ~feof(fid)
                line = fgetl(fid);
                if ~ischar(line) || isempty(strtrim(line))
                    continue;
                end
                line = strrep(line, sprintf('\r'), '');
                lineNum = lineNum + 1;

                % 跳过 key : value 头行（含冒号）
                if contains(line, ':')
                    if isempty(headerCandidate) && contains(line, '_')
                        headerCandidate = line;
                    end
                    continue;
                end

                parts = str2double(strsplit(line, {'\t', ' ', ','}));
                if ~all(isnan(parts))
                    dataLines{end+1} = parts; %#ok<AGROW>
                elseif isempty(headerCandidate) && contains(line, '_')
                    headerCandidate = line;
                end
            end

            if isempty(dataLines)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', ...
                    'GenericText: no numeric data found');
            end

            nCols = length(dataLines{1});
            data = nan(length(dataLines), nCols);
            for i = 1:length(dataLines)
                row = dataLines{i};
                n = min(length(row), nCols);
                data(i, 1:n) = row(1:n);
            end

            if ~isempty(headerCandidate)
                rawNames = strsplit(headerCandidate, {'\t', ' ', ','});
                for i = 1:length(rawNames)
                    name = strtrim(rawNames{i});
                    if ~isempty(name)
                        columnNames{end+1} = name; %#ok<AGROW>
                    end
                end
            end
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
        % ParseCsvFile CSV 格式（自动检测头行数）

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 自动检测头行数：逐行读取，首个纯数值行即为数据起始
            headerLines = {};
            numHeaderLines = 0;
            lastHeaderLine = '';
            for i = 1:100
                tline = fgetl(fid);
                if ~ischar(tline), break; end
                parts = strsplit(tline, {',', '\t'});
                nums = str2double(parts);
                if ~any(isnan(nums)) && ~isempty(nums)
                    % 纯数值行 → 数据开始
                    numHeaderLines = i - 1;
                    break;
                end
                headerLines{end+1} = tline; %#ok<AGROW>
                lastHeaderLine = tline;
            end

            % 从最后一个头行提取列名
            columnNames = {};
            if ~isempty(lastHeaderLine)
                parts = strsplit(lastHeaderLine, {',', '\t'});
                for k = 1:length(parts)
                    name = strtrim(parts{k});
                    if ~isempty(name) && isnan(str2double(name))
                        columnNames{end+1} = name; %#ok<AGROW>
                    end
                end
            end

            % 关闭文件后用 readmatrix 读数据
            clear cleanup;

            if exist('readmatrix', 'file')
                data = readmatrix(filePath, 'NumHeaderLines', numHeaderLines);
            else
                data = csvread(filePath, numHeaderLines, 0);
            end

            formatTag = 'acs_csv';
        end

        function [data, columnNames, formatTag] = ParseMatFile(filePath)
        % ParseMatFile .mat 格式解析
        %
        % 优先级：
        %   1. data 变量（标准化格式，直接使用）
        %   2. 收集所有数值向量（≥2行），按长度分组，最长组合并（列名取变量名）
        %   3. 单个数值矩阵 → 直接使用（列名：varName_1, varName_2, ...）

            loaded = load(filePath);

            % 1. 标准化格式
            if isfield(loaded, 'data') && isnumeric(loaded.data) && ismatrix(loaded.data)
                data = loaded.data;
                columnNames = {};
                formatTag = 'mat_standardized';
                return;
            end

            % 2. 收集数值向量（排除标量和非数值变量）
            fields = fieldnames(loaded);
            vecs = {};    % {struct('name',..., 'data',...), ...}
            matrices = {};
            for i = 1:length(fields)
                fname = fields{i};
                val = loaded.(fname);
                if ~isnumeric(val) || ~isreal(val), continue; end
                val = double(val);
                n = numel(val);
                if n >= 2 && isvector(val)
                    vecs{end+1} = struct('name', fname, 'data', val(:), 'len', n); %#ok<AGROW>
                elseif ismatrix(val) && numel(val) >= 2
                    matrices{end+1} = struct('name', fname, 'data', val); %#ok<AGROW>
                end
            end

            % 按长度分组，取最长的组合并（列名取变量名）
            if ~isempty(vecs)
                lengths = cellfun(@(v) v.len, vecs);
                maxLen = max(lengths);
                longest = vecs(lengths == maxLen);

                if length(longest) >= 1
                    dataArrays = cellfun(@(v) v.data, longest, 'UniformOutput', false);
                    data = cat(2, dataArrays{:});
                    columnNames = cellfun(@(v) v.name, longest, 'UniformOutput', false);
                    formatTag = 'mat';
                    return;
                end
            end

            % 3. 单个矩阵（列名：varName_1, varName_2, ...）
            if ~isempty(matrices)
                data = matrices{1}.data;
                varName = matrices{1}.name;
                nCols = size(data, 2);
                columnNames = arrayfun(@(i) sprintf('%s_%d', varName, i), ...
                    1:nCols, 'UniformOutput', false);
                formatTag = 'mat';
                return;
            end

            error('SignalAnalysis:DataReaderFactory:NoNumericData', ...
                'No numeric data found in .mat file');
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
                        % 保留原始列名（含=>），由 MatchColumnNames 统一简化
                        names{end+1} = name; %#ok<AGROW>
                    end
                    if ~isempty(names)
                        columnNames = names;
                    end
                catch ME
                    warning('DataReaderFactory:HeaderParseFailed', ...
                        '表头解析失败，使用默认列名: %s', ME.message);
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

            if ~isempty(titleLine) && contains(titleLine, 'DSA_data')
                % DSA FRF 频响数据：列角色固定 [amp, phase, corr, freq]
                formatTag = 'dsa_frf';
            else
                formatTag = 'fdot_text';
            end
        end

        function [data, columnNames, formatTag] = ParseSwppText(filePath)
        % ParseSwppText SWPP 文本格式：5行元数据 + N行列名（含[m]单位行）+ 空格/制表符分隔数据

            fid = fopen(filePath, 'r');
            if fid < 0
                error('SignalAnalysis:DataReaderFactory:FileOpenFailed', ...
                    'Cannot open file: %s', filePath);
            end
            cleanup = onCleanup(@() fclose(fid));

            % 读取5行元数据
            fgetl(fid);              % Graphic_Viewer
            fgetl(fid);              % 2026_07_22_06_53_00
            fgetl(fid);              % auto_saved
            numColsStr = fgetl(fid); % 12
            fgetl(fid);              % 2048
            if ~ischar(numColsStr)
                error('SignalAnalysis:DataReaderFactory:ParseFailed', 'SWPP header too short');
            end

            numCols = str2double(numColsStr);
            if isnan(numCols) || numCols < 1
                numCols = 0;
            end

            % 读取列名（每个通道两行：名称行 + [unit] 行）
            columnNames = {};
            for i = 1:numCols
                nameLine = fgetl(fid);
                unitLine = fgetl(fid);
                if ~ischar(nameLine), break; end
                columnNames{end+1} = strtrim(nameLine); %#ok<AGROW>
            end

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
        %
        % 自动提取头部列名（如有）：
        %   - 尝试从头部读取 numCols 声明，提取后续列名行
        %   - 无声明时按非数值行启发式提取

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

            % 从头部提取列名
            columnNames = DataReaderFactory.ExtractMultiSectionNames(allLines, dataStartIdx);

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

            formatTag = 'multi_section';
        end

        function columnNames = ExtractMultiSectionNames(allLines, dataStartIdx)
        % ExtractMultiSectionNames 从头部提取列名
        %
        % 策略：
        %   1. 在头部查找纯数字行（声明 numCols），其后2*numCols行为列名+单位
        %   2. 无声明时，提取数据行前所有非数值、非空行

            columnNames = {};

            if dataStartIdx <= 1
                return;
            end

            headerLines = allLines(1:dataStartIdx-1);

            % 策略1：查找纯数字行作为 numCols 声明
            numCols = 0;
            numColsLine = 0;
            for i = 1:length(headerLines)
                val = str2double(strtrim(headerLines{i}));
                if ~isnan(val) && val == round(val) && val > 0 && val < 1000
                    numCols = val;
                    numColsLine = i;
                    break;
                end
            end

            if numCols > 0 && numColsLine > 0
                % numColsLine 之后可能有行数声明（纯数字），跳过
                nameStart = numColsLine + 1;
                while nameStart <= length(headerLines)
                    val = str2double(strtrim(headerLines{nameStart}));
                    if ~isnan(val) && val == round(val) && val > 0
                        nameStart = nameStart + 1;
                    else
                        break;
                    end
                end
                % 从 nameStart 起提取列名（跳过单位行和空行）
                nameEnd = length(headerLines);
                idx = 0;
                for i = nameStart:nameEnd
                    line = strtrim(headerLines{i});
                    if isempty(line) || startsWith(line, '[')
                        continue;
                    end
                    if ~isnan(str2double(line))
                        continue;
                    end
                    idx = idx + 1;
                    if idx <= numCols
                        columnNames{idx} = line; %#ok<AGROW>
                    end
                    if idx >= numCols
                        break;
                    end
                end
            else
                % 策略2：提取数据行前所有非数值文本行
                for i = 1:length(headerLines)
                    line = strtrim(headerLines{i});
                    if isempty(line), continue; end
                    if ~isnan(str2double(line)), continue; end
                    if startsWith(line, '['), continue; end
                    columnNames{end+1} = line; %#ok<AGROW>
                end
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

        function columnNames = ExtractHeaderColumnNames(filePath, nDataCols)
        % ExtractHeaderColumnNames 从文件头独立提取列名
        %
        % 通用策略：找到数据起始行，从头部提取列名
        % 支持格式：
        %   - trace格式：numCols声明 + 名称/单位交替行
        %   - FDOT文本：第2行tab分隔列名
        %   - 启发式：数据行前的非数值文本行

            columnNames = {};

            fid = fopen(filePath, 'r');
            if fid < 0, return; end
            cleanup = onCleanup(@() fclose(fid));

            allLines = {};
            while ~feof(fid)
                line = fgetl(fid);
                if ischar(line)
                    allLines{end+1} = line; %#ok<AGROW>
                end
            end

            if length(allLines) < 2, return; end

            % 找数据起始行（跳过含字母/括号/冒号的行）
            dataStartIdx = 0;
            for i = 1:length(allLines)
                line = strtrim(allLines{i});
                if isempty(line), continue; end
                if ~isempty(regexp(line, '[a-zA-Z\[\]():]', 'once')), continue; end
                parts = str2double(strsplit(line));
                if ~all(isnan(parts)) && length(parts) >= 1
                    dataStartIdx = i;
                    break;
                end
            end
            if dataStartIdx <= 1, return; end

            headerLines = allLines(1:dataStartIdx-1);

            % 策略1：trace格式——查找 numCols 声明
            numColsLine = 0;
            for i = 1:length(headerLines)
                val = str2double(strtrim(headerLines{i}));
                if ~isnan(val) && val == round(val) && val > 0 && val < 1000
                    numColsLine = i;
                    break;
                end
            end

            if numColsLine > 0
                % 跳过声明后的纯数字行（如行数声明）
                nameStart = numColsLine + 1;
                while nameStart <= length(headerLines)
                    val = str2double(strtrim(headerLines{nameStart}));
                    if ~isnan(val) && val == round(val) && val > 0
                        nameStart = nameStart + 1;
                    else
                        break;
                    end
                end
                % 提取列名（跳过单位行、空行、纯数字行）
                names = {};
                for i = nameStart:length(headerLines)
                    line = strtrim(headerLines{i});
                    if isempty(line) || startsWith(line, '['), continue; end
                    if ~isnan(str2double(line)), continue; end
                    names{end+1} = line; %#ok<AGROW>
                end
                if ~isempty(names)
                    columnNames = names;
                    return;
                end
            end

            % 策略2：FDOT文本——第2行含tab分隔列名
            if length(headerLines) >= 2
                line2 = headerLines{2};
                if contains(line2, sprintf('\t'))
                    parts = strsplit(strtrim(line2), '\t');
                    names = {};
                    for i = 1:length(parts)
                        n = strtrim(parts{i});
                        if ~isempty(n)
                            names{end+1} = n; %#ok<AGROW>
                        end
                    end
                    if length(names) >= 2
                        columnNames = names;
                        return;
                    end
                end
            end

            % 策略3：启发式——含下划线的文本行
            names = {};
            for i = 1:length(headerLines)
                line = strtrim(headerLines{i});
                if isempty(line), continue; end
                if ~isnan(str2double(line)), continue; end
                % key : value 参数行（含或不含方括号）：提取关键字后缀
                if contains(line, ':')
                    suffix = DataReaderFactory.ExtractTraceSuffix(line, ...
                        DataReaderFactory.GetKeywords());
                    if ~isempty(suffix) && isnan(str2double(suffix))
                        names{end+1} = suffix; %#ok<AGROW>
                    end
                    continue;
                end
                % 普通文本行：含下划线且长度>4
                if contains(line, '_') && length(line) > 4
                    names{end+1} = line; %#ok<AGROW>
                end
            end
            if ~isempty(names) && length(names) >= nDataCols - 1
                if length(names) > nDataCols
                    % 列名多于数据列：合并为一个
                    columnNames = {strjoin(names, '_')};
                else
                    columnNames = names;
                end
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

        function result = StripKeywordPrefix(name, keywords)
        % StripKeywordPrefix 仅剥离开头关键字
        %
        % 检查第一个 _ 分段是否为关键字（大小写不敏感），
        % 若是则剥离，否则返回原名。

            parts = strsplit(name, '_');
            if ischar(parts), parts = {parts}; end
            if isempty(parts), result = name; return; end

            if any(cellfun(@(kw) strcmpi(strtrim(parts{1}), kw), keywords))
                if length(parts) > 1
                    result = strjoin(parts(2:end), '_');
                else
                    result = name;
                end
            else
                result = name;
            end
        end

        function result = StripUpToKeyword(name, keywords)
        % StripUpToKeyword 找到第一个关键字（任意位置），取其右边
        %
        % 'Y1_CTRL_ERROR'  → 'ERROR'       （找到 CTRL，取右边）
        % 'SN_IFM_X1'      → 'IFM_X1'     （找到 SN，取右边）
        % 'BLADE_AX_Y2'    → 'BLADE_AX_Y2'（无关键字，保留原名）

            parts = strsplit(name, '_');
            if ischar(parts), parts = {parts}; end

            for i = 1:length(parts)
                seg = strtrim(parts{i});
                if any(cellfun(@(kw) strcmpi(seg, kw), keywords))
                    if i < length(parts)
                        result = strjoin(parts(i+1:end), '_');
                        return;
                    end
                end
            end
            result = name;
        end

        function result = TrailingSegment(name)
        % TrailingSegment 取最后一个 _ 分段
        %
        % 'AX_Y2'       → 'Y2'
        % 'BLADE_AX_Y2' → 'Y2'
        % 'ERROR'       → 'ERROR'

            parts = strsplit(name, '_');
            if ischar(parts), parts = {parts}; end
            result = parts{end};
        end

        function result = StripVendorPrefix(name, prefixes)
        % StripVendorPrefix 剥离厂商前缀（大小写不敏感）
        %
        % 前缀列表可配置，默认从 simplifyStorage 读取

            if nargin < 2 || isempty(prefixes)
                prefixes = DataReaderFactory.GetVendorPrefixes();
            end
            result = name;
            for k = 1:length(prefixes)
                if strncmpi(result, prefixes{k}, length(prefixes{k}))
                    result = result(length(prefixes{k})+1:end);
                    break;
                end
            end
        end

        function cleaned = CleanRawName(rawName, keywords, separators)
        % CleanRawName 统一列名清理管线
        %
        % 管线：StripVendorPrefix → 分隔符检测 → 关键字剥离
        %
        % 'CTRL_ERROR'              → 'ERROR'
        % 'Y1_CTRL_ERROR'           → 'Y1_CTRL_ERROR'
        % 'VM4A_BLADE_AX_Y2=>CTRL_ERROR' → 'Y2_ERROR'
        % 'VM4A_CTRLVAR_CTRL_ERROR' → 'CTRL_ERROR'
        % 'BLADE_AX_Y2'             → 'BLADE_AX_Y2'

            if nargin < 2 || isempty(keywords), keywords = DataReaderFactory.GetKeywords(); end
            if nargin < 3 || isempty(separators), separators = DataReaderFactory.GetSeparators(); end

            % Step 1: 去除厂商前缀
            name = DataReaderFactory.StripVendorPrefix(rawName);

            % Step 2: 检测分隔符
            sepFound = '';
            sepPos = 0;
            for s = 1:length(separators)
                idx = strfind(name, separators{s});
                if ~isempty(idx)
                    sepFound = separators{s};
                    sepPos = idx(1);
                    break;
                end
            end

            if ~isempty(sepFound)
                % Step 3a: 有分隔符 → 两边各自独立清理
                leftPart = name(1:sepPos-1);
                rightPart = name(sepPos+length(sepFound):end);

                leftPart = DataReaderFactory.StripVendorPrefix(leftPart);
                rightPart = DataReaderFactory.StripVendorPrefix(rightPart);

                leftClean = DataReaderFactory.TrailingSegment(...
                    DataReaderFactory.StripKeywordPrefix(leftPart, keywords));
                rightClean = DataReaderFactory.TrailingSegment(...
                    DataReaderFactory.StripKeywordPrefix(rightPart, keywords));

                cleaned = [leftClean '_' rightClean];
            else
                % Step 3b: 无分隔符 → StripKeywordPrefix
                cleaned = DataReaderFactory.StripKeywordPrefix(name, keywords);
            end

            % 空结果保护
            if isempty(cleaned)
                cleaned = rawName;
            end
        end

        function colNames = ExtractTraceColumnName(filePath)
        % ExtractTraceColumnName 从 trace 文件头提取列名
        %
        % 解析 ctrl.axis_id 和 ctrl.dvariable_id，分别清理后返回独立列名
        % 返回 cell 数组，如 {'Y1', 'CTRL_ERROR'}

            keywords = {'AX', 'CTRL', 'CTRLVAR'};
            axisPart = '';
            varPart = '';

            fid = fopen(filePath, 'r');
            if fid < 0
                colNames = {};
                return;
            end

            for i = 1:20
                tline = fgetl(fid);
                if ~ischar(tline), break; end

                if contains(tline, 'ctrl.axis_id')
                    axisPart = DataReaderFactory.ExtractTraceSuffix(tline, keywords);
                elseif contains(tline, 'ctrl.dvariable_id')
                    varPart = DataReaderFactory.ExtractTraceSuffix(tline, keywords);
                end
            end
            fclose(fid);

            colNames = {};
            if ~isempty(axisPart),  colNames{end+1} = axisPart; end
            if ~isempty(varPart),   colNames{end+1} = varPart; end
        end

        function suffix = ExtractTraceSuffix(line, keywords)
        % ExtractTraceSuffix 从 trace 头行提取冒号后的值，去前缀，找关键字取后缀
        %
        % 'ctrl.axis_id       :	4-(AXIS)VM4A_BLADE_AX_Y1' → 'Y1'
        % 'ctrl.dvariable_id  :	0-VM4A_CTRLVAR_CTRL_ERROR' → 'CTRL_ERROR'

            suffix = '';
            colonIdx = strfind(line, ':');
            if isempty(colonIdx), return; end
            value = strtrim(line(colonIdx(1)+1:end));

            % 去掉前缀编号如 '4-(AXIS)' 或 '5-'
            dashIdx = strfind(value, '-');
            if ~isempty(dashIdx) && dashIdx(1) <= 3
                value = strtrim(value(dashIdx(1)+1:end));
            end

            % 去掉 (AXIS) 等括号前缀
            parenEnd = strfind(value, ')');
            if ~isempty(parenEnd)
                value = strtrim(value(parenEnd(1)+1:end));
            end

            % 去掉常见厂商前缀（可配置）
            value = DataReaderFactory.StripVendorPrefix(value);

            % StripUpToKeyword：找任意位置关键字，取右边
            suffix = DataReaderFactory.StripUpToKeyword(value, keywords);

            % 没匹配到关键字时返回空（避免噪声行被当作列名）
            if strcmp(suffix, value)
                suffix = '';
            end
        end

        function names = DeduplicateNames(names, ignoreCase)
        % DeduplicateNames 对重复名称加后缀 _2, _3 ...
        %
        % 输入：
        %   names      - cell of char
        %   ignoreCase - logical，是否大小写不敏感（默认 true）
        %
        % {'CTRL', 'CTRL', 'SENSOR'}       → {'CTRL', 'CTRL_2', 'SENSOR'}
        % {'ctrl', 'CTRL', 'SENSOR'} (ignoreCase=true) → {'ctrl', 'CTRL_2', 'SENSOR'}

            if nargin < 2, ignoreCase = true; end

            seen = containers.Map('KeyType', 'char', 'ValueType', 'double');
            for i = 1:length(names)
                name = names{i};
                if ignoreCase
                    key = lower(name);
                else
                    key = name;
                end
                if isKey(seen, key)
                    count = seen(key) + 1;
                    seen(key) = count;
                    names{i} = sprintf('%s_%d', name, count);
                else
                    seen(key) = 1;
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
