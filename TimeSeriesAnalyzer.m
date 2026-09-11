classdef TimeSeriesAnalyzer < handle
% TimeSeriesAnalyzer - 主分析工具 GUI
%
% 多文件多通道叠加分析。programmatic UI，动态 axes（1-6）。
% 左面板：通道池（按文件/子文件夹分组，checkbox 勾选叠加到 axes）。
% 右面板：多 axes 视图，选区，状态栏。

    properties (SetAccess = private)
        MainFigure          % 主图窗 handle
        Session         SessionData
        PlotCtrl        PlotController
        SelectionMgr    SelectionManager
        AnalysisEngine_ AnalysisEngine

        % UI 控件
        ChannelPanel            % uipanel 通道列表容器
        ChannelControls   cell  % 通道控件 struct array: {handle, type, datasetIdx, colIdx}
        DatasetExpanded_  logical  % 每个数据集的展开状态
        AxesTabBars       cell  % 每个 axes 的标签按钮 handles
        SelectionPanel          % uipanel handle
        SelectionStartEdit      % uicontrol handle
        SelectionEndEdit        % uicontrol handle
        StatusBar               % uicontrol handle

        % 布局
        LeftPanel               % uipanel handle
        RightPanel              % uipanel handle
        AxesContainer           % uipanel handle

        % 分析类型记录（每个 axes 独立）
        AxesAnalysisType cell   % {'time','fft','psd',...} per axes

        % 归一化控件
        NormModeDropdown        % uicontrol popup 归一化模式选择
        NormButton              % uicontrol pushbutton 归一化按钮
    end

    methods
        function obj = TimeSeriesAnalyzer()
            obj.Session = SessionData(6);
            obj.ChannelControls = {};
            obj.DatasetExpanded_ = logical([]);
            obj.AxesTabBars = {};
            obj.AxesAnalysisType = {};

            obj.BuildUI();
            obj.PlotCtrl = PlotController(obj.MainFigure, 6, obj.AxesContainer);
            obj.SelectionMgr = SelectionManager(obj.Session, obj.PlotCtrl);
            obj.AnalysisEngine_ = AnalysisEngine(obj.Session, obj.PlotCtrl);

            % 注册事件
            addlistener(obj.Session, 'DatasetsUpdated', @obj.OnDatasetsUpdated);
            addlistener(obj.Session, 'ChannelsUpdated', @obj.OnChannelsUpdated);
            addlistener(obj.Session, 'SelectionChanged', @obj.OnSelectionChanged);
        end

        function BuildUI(obj)
            % 主图窗
            obj.MainFigure = figure( ...
                'Name', 'Signal Analysis - Time Series', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'none', ...
                'Position', [100 100 1200 700], ...
                'KeyPressFcn', @obj.OnKeyPress, ...
                'CloseRequestFcn', @obj.OnClose);

            % 左面板（通道池）
            obj.LeftPanel = uipanel(obj.MainFigure, ...
                'Position', [0 0 0.2 1], ...
                'Title', '');

            % 通道列表区域（滚动面板）
            obj.ChannelPanel = uipanel(obj.LeftPanel, ...
                'Position', [0 0.12 1 0.88], ...
                'Title', '');

            % 底部按钮（3行布局）
            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Browse...', ...
                'Units', 'normalized', ...
                'Position', [0 0.12 1 0.04], ...
                'Callback', @obj.OnBrowseFile);

            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Retry', ...
                'Units', 'normalized', ...
                'Position', [0 0.075 1 0.04], ...
                'Callback', @obj.OnRetry);

            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Import', ...
                'Units', 'normalized', ...
                'Position', [0 0.005 0.48 0.04], ...
                'Callback', @obj.OnImportFile);

            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Clear All', ...
                'Units', 'normalized', ...
                'Position', [0.5 0.005 0.48 0.04], ...
                'Callback', @obj.OnClearAll);

            % 右面板（绘图区 + 选区 + 状态栏）
            obj.RightPanel = uipanel(obj.MainFigure, ...
                'Position', [0.2 0 0.8 1], ...
                'Title', '');

            % 工具栏
            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', '+', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.96 0.04 0.03], ...
                'Callback', @obj.OnAddAxes, ...
                'FontSize', 12, 'FontWeight', 'bold');

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'x', ...
                'Units', 'normalized', ...
                'Position', [0.06 0.96 0.04 0.03], ...
                'Callback', @obj.OnRemoveAxes, ...
                'FontSize', 10);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', '||', ...
                'Units', 'normalized', ...
                'Position', [0.11 0.96 0.04 0.03], ...
                'Callback', @obj.OnLayoutVertical);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', '=', ...
                'Units', 'normalized', ...
                'Position', [0.16 0.96 0.04 0.03], ...
                'Callback', @obj.OnLayoutHorizontal);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Export', ...
                'Units', 'normalized', ...
                'Position', [0.55 0.96 0.08 0.03], ...
                'Callback', @obj.OnExportFigure);

            % 归一化模式下拉框
            obj.NormModeDropdown = uicontrol(obj.RightPanel, 'Style', 'popupmenu', ...
                'String', {'None', 'Min-Max', 'Z-Score', 'Mean Zero'}, ...
                'Value', 1, ...
                'Units', 'normalized', ...
                'Position', [0.65 0.96 0.12 0.03], ...
                'FontSize', 8);

            % 归一化按钮
            obj.NormButton = uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Norm', ...
                'Units', 'normalized', ...
                'Position', [0.78 0.96 0.06 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnNormalizeAxes);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Calc', ...
                'Units', 'normalized', ...
                'Position', [0.85 0.96 0.06 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnCalcChannel);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Undo', ...
                'Units', 'normalized', ...
                'Position', [0.92 0.96 0.06 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnUndo);

            % Axes 容器
            obj.AxesContainer = uipanel(obj.RightPanel, ...
                'Position', [0 0.12 1 0.83], ...
                'Title', '', ...
                'BorderType', 'none');

            % 选区面板
            obj.SelectionPanel = uipanel(obj.RightPanel, ...
                'Position', [0 0.06 1 0.06], ...
                'Title', 'Selection');

            uicontrol(obj.SelectionPanel, 'Style', 'text', ...
                'String', 'Start:', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.2 0.08 0.6], ...
                'HorizontalAlignment', 'left');

            obj.SelectionStartEdit = uicontrol(obj.SelectionPanel, 'Style', 'edit', ...
                'Units', 'normalized', ...
                'Position', [0.09 0.1 0.15 0.8], ...
                'Callback', @obj.OnSelectionStartChanged);

            uicontrol(obj.SelectionPanel, 'Style', 'text', ...
                'String', 'End:', ...
                'Units', 'normalized', ...
                'Position', [0.26 0.2 0.08 0.6], ...
                'HorizontalAlignment', 'left');

            obj.SelectionEndEdit = uicontrol(obj.SelectionPanel, 'Style', 'edit', ...
                'Units', 'normalized', ...
                'Position', [0.34 0.1 0.15 0.8], ...
                'Callback', @obj.OnSelectionEndChanged);

            uicontrol(obj.SelectionPanel, 'Style', 'pushbutton', ...
                'String', 'Apply', ...
                'Units', 'normalized', ...
                'Position', [0.52 0.1 0.1 0.8], ...
                'Callback', @obj.OnApplySelection);

            uicontrol(obj.SelectionPanel, 'Style', 'pushbutton', ...
                'String', 'Undo', ...
                'Units', 'normalized', ...
                'Position', [0.64 0.1 0.1 0.8], ...
                'Callback', @obj.OnUndoSelection);

            % 状态栏
            obj.StatusBar = uicontrol(obj.RightPanel, 'Style', 'text', ...
                'String', 'Ready', ...
                'Units', 'normalized', ...
                'Position', [0 0 1 0.05], ...
                'HorizontalAlignment', 'left', ...
                'BackgroundColor', [0.94 0.94 0.94]);
        end

        % ---- 通道池 UI ----

        function RebuildChannelList(obj)
        % RebuildChannelList 重建通道列表（按数据集分组，默认折叠）

            % 删除旧控件
            for i = 1:length(obj.ChannelControls)
                h = obj.ChannelControls{i}.handle;
                if isvalid(h)
                    delete(h);
                end
            end
            obj.ChannelControls = {};

            nDatasets = obj.Session.DatasetCount;
            if nDatasets == 0
                return;
            end

            % 初始化展开状态（默认折叠）
            if isempty(obj.DatasetExpanded_) || length(obj.DatasetExpanded_) ~= nDatasets
                obj.DatasetExpanded_ = false(1, nDatasets);
            end

            yPos = 0.96;
            lineH = 0.035;
            headerH = 0.04;

            for d = 1:nDatasets
                dsName = obj.Session.GetDatasetName(d);
                ds = obj.Session.GetDataset(d);
                nCols = ds.ColumnCount;
                expanded = obj.DatasetExpanded_(d);

                % 截断长名称
                maxLen = 15;
                if length(dsName) > maxLen
                    displayName = [dsName(1:maxLen) '...'];
                else
                    displayName = dsName;
                end

                % 标题行（可点击展开/折叠）
                if expanded
                    arrow = '▼';
                else
                    arrow = '▶';
                end
                headerText = sprintf('%s %s (%d)', arrow, displayName, nCols);
                h = uicontrol(obj.ChannelPanel, 'Style', 'pushbutton', ...
                    'String', headerText, ...
                    'Units', 'normalized', ...
                    'Position', [0 yPos 1 headerH], ...
                    'HorizontalAlignment', 'left', ...
                    'FontSize', 8, ...
                    'TooltipString', dsName, ...
                    'Callback', @(src, evt) obj.OnToggleDataset(d));

                % 数据集标题右键菜单
                cm = uicontextmenu(obj.MainFigure);
                uimenu(cm, 'Text', '设置采样率...', ...
                    'Callback', @(src, evt) obj.OnSetSampleRate(d));
                set(h, 'UIContextMenu', cm);

                obj.ChannelControls{end+1} = struct('handle', h, 'type', 'header', ...
                    'datasetIdx', d, 'colIdx', 0);
                yPos = yPos - headerH;

                % 展开时显示通道
                if expanded
                    for c = 1:nCols
                        % 检查是否有切片标记
                        sliceTag = '';
                        chansOnAxes = obj.Session.GetAxesChannels(obj.Session.FocusedAxes);
                        for sc = 1:length(chansOnAxes)
                            if chansOnAxes{sc}.DatasetIdx == d && chansOnAxes{sc}.ColIdx == c
                                if isfield(chansOnAxes{sc}, 'SliceRange')
                                    sr = chansOnAxes{sc}.SliceRange;
                                    if sr(1) > 1 || sr(2) < length(chansOnAxes{sc}.Data)
                                        sliceTag = ' [S]';
                                    end
                                end
                                break;
                            end
                        end

                        label = sprintf('%d: %s%s', c, ds.GetColumnName(c), sliceTag);
                        h = uicontrol(obj.ChannelPanel, 'Style', 'checkbox', ...
                            'String', label, ...
                            'Units', 'normalized', ...
                            'Position', [0.05 yPos 0.93 lineH], ...
                            'Value', 0, ...
                            'FontSize', 8, ...
                            'Callback', @(src, evt) obj.OnChannelCheckbox(d, c, src));

                        % 注册右键菜单（切片）
                        cm = uicontextmenu(obj.MainFigure);
                        uimenu(cm, 'Text', '设置切片范围...', ...
                            'Callback', @(src, evt) obj.OnChannelSliceDialog(d, c));
                        uimenu(cm, 'Text', '切片重置', ...
                            'Callback', @(src, evt) obj.OnChannelSliceReset(d, c));
                        set(h, 'UIContextMenu', cm);
                        obj.ChannelControls{end+1} = struct('handle', h, 'type', 'checkbox', ...
                            'datasetIdx', d, 'colIdx', c);
                        yPos = yPos - lineH;

                        if yPos < 0
                            break;
                        end
                    end
                end
                if yPos < 0
                    break;
                end
            end
        end

        % ---- Axes Tab 栏 ----

        function CreateAxesTabBar(obj, axesIdx)
            while length(obj.AxesTabBars) < axesIdx
                obj.AxesTabBars{end+1} = {}; %#ok<AGROW>
                obj.AxesAnalysisType{end+1} = 'time'; %#ok<AGROW>
            end

            tabTypes = {'Time', 'FFT', 'PSD', 'Integral', 'MADSD'};
            tabWidth = 0.08;
            startX = 0.01;

            buttons = {};
            for i = 1:length(tabTypes)
                btn = uicontrol(obj.AxesContainer, 'Style', 'pushbutton', ...
                    'String', tabTypes{i}, ...
                    'Units', 'normalized', ...
                    'Position', [startX + (i-1)*tabWidth, 0.96, tabWidth, 0.03], ...
                    'FontSize', 8, ...
                    'Callback', @(src, evt) obj.OnAnalysisTabClicked(axesIdx, lower(tabTypes{i})));
                buttons{end+1} = btn; %#ok<AGROW>
            end
            obj.AxesTabBars{axesIdx} = buttons;
            obj.AxesAnalysisType{axesIdx} = 'time';
        end

        function SetupAxesClickFocus(obj, axesIdx)
        % SetupAxesClickFocus 注册 axes 点击聚焦回调
            callback = @(src, evt) obj.OnAxesClicked(axesIdx);
            obj.PlotCtrl.SetAxesClickCallback(axesIdx, callback);
        end
    end

    % Callbacks
    methods (Access = private)
        function OnClose(obj, ~, ~)
            delete(obj.MainFigure);
        end

        function OnKeyPress(obj, ~, evt)
            switch evt.Key
                case 'o'
                    if any(strcmp(evt.Modifier, 'control'))
                        obj.OnBrowseFile([], []);
                    end
                case 'e'
                    if any(strcmp(evt.Modifier, 'control'))
                        obj.OnExportFigure([], []);
                    end
                case 'z'
                    if any(strcmp(evt.Modifier, 'control'))
                        obj.OnUndo([], []);
                    end
                case {'1','2','3','4','5','6'}
                    idx = str2double(evt.Key);
                    if idx <= obj.PlotCtrl.GetAxesCount()
                        obj.Session.SetFocusedAxes(idx);
                    end
                case 'f'
                    axIdx = obj.Session.FocusedAxes;
                    obj.OnAnalysisTabClicked(axIdx, 'fft');
                case 'p'
                    axIdx = obj.Session.FocusedAxes;
                    obj.OnAnalysisTabClicked(axIdx, 'psd');
                case 't'
                    axIdx = obj.Session.FocusedAxes;
                    obj.OnAnalysisTabClicked(axIdx, 'time');
                case 'delete'
                    axIdx = obj.Session.FocusedAxes;
                    obj.PlotCtrl.ClearAxes(axIdx);
                    obj.Session.ClearAxes(axIdx);
            end
        end

        function OnDatasetsUpdated(obj, ~, ~)
        % OnDatasetsUpdated 数据集变更
            obj.RebuildChannelList();
            obj.UpdateStatusBar();
        end

        function OnChannelsUpdated(obj, ~, ~)
        % OnChannelsUpdated axes 通道变更
            obj.UpdateStatusBar();
        end

        function OnSelectionChanged(obj, ~, ~)
        % OnSelectionChanged 选区变更
            range = obj.Session.SelectionRange;

            % 更新编辑框（用第一个数据集的采样率换算时间）
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                sampleTime = ds.SampleTime;
                set(obj.SelectionStartEdit, 'String', ...
                    sprintf('%.6f', range(1) * sampleTime));
                set(obj.SelectionEndEdit, 'String', ...
                    sprintf('%.6f', range(2) * sampleTime));
            end

            % 刷新所有 axes
            obj.AnalysisEngine_.RefreshAll();
            obj.UpdateStatusBar();
        end

        function OnAxesClicked(obj, axesIdx)
        % OnAxesClicked axes 点击聚焦
            obj.Session.SetFocusedAxes(axesIdx);
        end

        function OnChannelCheckbox(obj, datasetIdx, colIdx, src)
        % OnChannelCheckbox 通道 checkbox 勾选/取消
            val = get(src, 'Value');
            axIdx = obj.Session.FocusedAxes;

            if val
                % 勾选：叠加到当前聚焦 axes
                obj.Session.AddChannelToAxes(axIdx, datasetIdx, colIdx);

                % 确保 axes 存在
                while obj.PlotCtrl.GetAxesCount() < axIdx
                    idx = obj.PlotCtrl.AddAxes();
                    obj.Session.AddAxes();
                    obj.CreateAxesTabBar(idx);
                    obj.SetupAxesClickFocus(idx);
                end

                % 运行分析
                analysisType = 'time';
                if axIdx <= length(obj.AxesAnalysisType) && ~isempty(obj.AxesAnalysisType{axIdx})
                    analysisType = obj.AxesAnalysisType{axIdx};
                end
                obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
            else
                % 取消勾选：从 axes 移除该通道
                obj.Session.RemoveChannelFromAxes(axIdx, datasetIdx, colIdx);
                % 重绘
                analysisType = 'time';
                if axIdx <= length(obj.AxesAnalysisType) && ~isempty(obj.AxesAnalysisType{axIdx})
                    analysisType = obj.AxesAnalysisType{axIdx};
                end
                chans = obj.Session.GetAxesChannels(axIdx);
                if isempty(chans)
                    obj.PlotCtrl.ClearAxes(axIdx);
                else
                    obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
                end
            end
        end

        function OnAnalysisTabClicked(obj, axesIdx, analysisType)
        % OnAnalysisTabClicked 分析类型标签点击
            while length(obj.AxesAnalysisType) < axesIdx
                obj.AxesAnalysisType{end+1} = 'time'; %#ok<AGROW>
            end
            obj.AxesAnalysisType{axesIdx} = analysisType;

            chans = obj.Session.GetAxesChannels(axesIdx);
            if ~isempty(chans)
                obj.AnalysisEngine_.RunAnalysis(axesIdx, analysisType);
            end
        end

        function OnBrowseFile(obj, ~, ~)
            try
                startPath = obj.Session.GetLastPath(1);
                if isempty(startPath)
                    startPath = pwd;
                end

                rootDir = FileExplorer.SelectFolder(startPath);
                if isempty(rootDir)
                    return;
                end

                obj.Session.SetLastPath(1, rootDir);

                % 批量导入（子文件夹感知）
                results = DataReaderFactory.BatchImportFolder(rootDir);

                if isempty(results)
                    errordlg('未找到可导入的数据文件', 'Error');
                    return;
                end

                % 将每个结果作为数据集加入 Session
                for i = 1:length(results)
                    ds = DataReaderFactory.LoadStandard(results(i).matPath);
                    obj.Session.AddDataset(ds, results(i).name, results(i).matPath);
                end

            catch e
                errordlg(sprintf('浏览文件夹失败:\n%s', e.message), 'Error');
            end
        end

        function OnImportFile(obj, ~, ~)
            startPath = obj.Session.GetLastPath(1);
            if isempty(startPath)
                startPath = pwd;
            end

            [fileName, filePath] = FileExplorer.SelectFile(startPath, ...
                'Data Files (*.dat;*.csv;*.txt;*.xlsx;*.mat)|*.dat;*.csv;*.txt;*.xlsx;*.mat');

            if ~isempty(filePath)
                try
                    outputDir = fileparts(filePath);
                    matPath = DataReaderFactory.ImportToStandard(filePath, outputDir);
                    ds = DataReaderFactory.LoadStandard(matPath);
                    [~, fname] = fileparts(filePath);
                    obj.Session.AddDataset(ds, fname, matPath);
                    obj.Session.SetLastPath(1, outputDir);
                catch e
                    errordlg(sprintf('导入失败:\n%s', e.message), 'Error');
                end
            end
        end

        function OnClearAll(obj, ~, ~)
        % OnClearAll 重置全部（清空数据集和 axes）
            obj.Session.ClearAllDatasets();
            obj.PlotCtrl.ClearAll();
            for i = 1:length(obj.AxesTabBars)
                for j = 1:length(obj.AxesTabBars{i})
                    if isvalid(obj.AxesTabBars{i}{j})
                        delete(obj.AxesTabBars{i}{j});
                    end
                end
            end
            obj.AxesTabBars = {};
            obj.AxesAnalysisType = {};
        end

        function OnToggleDataset(obj, dsIdx, ~)
        % OnToggleDataset 切换数据集展开/折叠状态
            if dsIdx >= 1 && dsIdx <= length(obj.DatasetExpanded_)
                obj.DatasetExpanded_(dsIdx) = ~obj.DatasetExpanded_(dsIdx);
                obj.RebuildChannelList();
            end
        end

        function OnRetry(obj, ~, ~)
        % OnRetry 重新读取 Excel，检测列名是否更新
        %
        % 遍历所有数据集，检查对应 Excel 文件的列名：
        %   Excel 有列名且与 .mat 不同 → 更新 .mat 并刷新显示
        %   Excel 列名全空或与 .mat 相同 → 跳过

            nDatasets = obj.Session.DatasetCount;
            if nDatasets == 0
                return;
            end

            updated = 0;
            for i = 1:nDatasets
                matPath = obj.Session.DatasetPaths_{i};
                if isempty(matPath) || ~exist(matPath, 'file')
                    continue;
                end

                % 推导 Excel 路径：xxx_standardized.mat → xxx_review.xlsx
                xlsxPath = strrep(matPath, '_standardized.mat', '_review.xlsx');
                if ~exist(xlsxPath, 'file')
                    continue;
                end

                try
                    % 读取 Excel 列名
                    if exist('readcell', 'file')
                        raw = readcell(xlsxPath);
                    else
                        [~, ~, raw] = xlsread(xlsxPath); %#ok<XLSRD>
                    end

                    nCols = size(raw, 2);
                    excelColNames = cell(1, nCols);
                    for c = 1:nCols
                        val = raw{1, c};
                        if (ischar(val) || isstring(val)) && ~isempty(strtrim(char(val)))
                            excelColNames{c} = strtrim(char(val));
                        end
                    end

                    % Excel 列名全空 → 跳过
                    if all(cellfun(@isempty, excelColNames))
                        continue;
                    end

                    % 读取 .mat 列名
                    loaded = load(matPath);
                    matColNames = {};
                    if isfield(loaded, 'sa_column_names')
                        matColNames = loaded.sa_column_names;
                    end

                    % 比较：Excel 列名与 .mat 不同 → 更新
                    if ~isequal(excelColNames, matColNames)
                        loaded.sa_column_names = excelColNames;
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

                        % 重新加载数据集
                        ds = DataReaderFactory.LoadStandard(matPath);
                        obj.Session.UpdateDataset(i, ds);
                        updated = updated + 1;
                    end
                catch
                    % 读取失败，跳过
                end
            end

            if updated > 0
                obj.RebuildChannelList();
                fprintf('[Retry] 更新了 %d 个数据集的列名\n', updated);
            end
        end

        function OnSetSampleRate(obj, datasetIdx)
        % OnSetSampleRate 右键数据集标题，设置采样率
            ds = obj.Session.GetDataset(datasetIdx);
            dsName = obj.Session.GetDatasetName(datasetIdx);
            currentRate = ds.SampleRate;

            if isempty(currentRate)
                defaultStr = '';
            else
                defaultStr = num2str(currentRate);
            end

            answer = inputdlg(sprintf('数据集: %s\n采样率 (Hz):', dsName), ...
                '设置采样率', 1, {defaultStr});
            if isempty(answer), return; end

            newRate = str2double(answer{1});
            if isnan(newRate) || newRate <= 0
                errordlg('采样率必须为正数', '错误');
                return;
            end

            % 更新 Dataset 对象
            obj.Session.UpdateSampleRate(datasetIdx, newRate);

            % 写回 .mat 文件
            matPath = obj.Session.DatasetPaths_{datasetIdx};
            if ~isempty(matPath) && exist(matPath, 'file')
                DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
            end

            % 写回 _meta.json
            jsonPath = strrep(matPath, '_standardized.mat', '_standardized_meta.json');
            if exist(jsonPath, 'file')
                try
                    meta = jsondecode(fileread(jsonPath));
                    meta.sample_rate = newRate;
                    DataReaderFactory.WriteJson(jsonPath, meta);
                catch
                end
            end

            fprintf('[SampleRate] %s → %.4g Hz\n', dsName, newRate);
        end

        function OnChannelSliceDialog(obj, datasetIdx, colIdx)
        % OnChannelSliceDialog 右键设置通道切片范围
            axIdx = obj.Session.FocusedAxes;
            chans = obj.Session.GetAxesChannels(axIdx);

            % 查找该通道在 axes 中的位置
            chanIdx = 0;
            for c = 1:length(chans)
                if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                    chanIdx = c;
                    break;
                end
            end
            if chanIdx == 0
                msgbox('请先勾选该通道到 axes', '提示');
                return;
            end

            chan = chans{chanIdx};
            totalRows = length(chan.Data);
            currentRange = chan.SliceRange;
            currentLen = currentRange(2) - currentRange(1) + 1;

            % 输入对话框：起点 + 长度
            answer = inputdlg({'起点行号:', '长度:'}, '设置切片范围', ...
                1, {num2str(currentRange(1)), num2str(currentLen)});
            if isempty(answer), return; end

            startRow = round(str2double(answer{1}));
            segLen = round(str2double(answer{2}));
            if isnan(startRow) || isnan(segLen) || startRow < 1 || segLen < 1 || startRow + segLen - 1 > totalRows
                errordlg(sprintf('范围无效 (起点 1~%d, 长度 ≥1)', totalRows), '错误');
                return;
            end
            endRow = startRow + segLen - 1;

            obj.Session.SetChannelSlice(axIdx, chanIdx, startRow, endRow);

            % 重绘
            analysisType = 'time';
            if axIdx <= length(obj.AxesAnalysisType) && ~isempty(obj.AxesAnalysisType{axIdx})
                analysisType = obj.AxesAnalysisType{axIdx};
            end
            obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
            obj.RebuildChannelList();
        end

        function OnChannelSliceReset(obj, datasetIdx, colIdx)
        % OnChannelSliceReset 重置通道切片
            axIdx = obj.Session.FocusedAxes;
            chans = obj.Session.GetAxesChannels(axIdx);

            chanIdx = 0;
            for c = 1:length(chans)
                if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                    chanIdx = c;
                    break;
                end
            end
            if chanIdx == 0, return; end

            chan = chans{chanIdx};
            obj.Session.SetChannelSlice(axIdx, chanIdx, 1, length(chan.Data));

            % 重绘
            analysisType = 'time';
            if axIdx <= length(obj.AxesAnalysisType) && ~isempty(obj.AxesAnalysisType{axIdx})
                analysisType = obj.AxesAnalysisType{axIdx};
            end
            obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
            obj.RebuildChannelList();
        end

        function OnNormalizeAxes(obj, ~, ~)
        % OnNormalizeAxes 归一化当前聚焦 axes
            axIdx = obj.Session.FocusedAxes;
            if axIdx < 1 || axIdx > obj.PlotCtrl.GetAxesCount()
                return;
            end

            % 获取选择的归一化模式
            modes = {'none', 'minmax', 'zscore', 'meanzero'};
            val = get(obj.NormModeDropdown, 'Value');
            normMode = modes{val};

            obj.Session.SetAxesNormMode(axIdx, normMode);

            if strcmpi(normMode, 'none')
                % 重绘恢复原始数据
                analysisType = 'time';
                if axIdx <= length(obj.AxesAnalysisType) && ~isempty(obj.AxesAnalysisType{axIdx})
                    analysisType = obj.AxesAnalysisType{axIdx};
                end
                obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
            else
                % 执行归一化
                obj.PlotCtrl.NormalizeAxes(axIdx, normMode, obj.Session);
            end
        end

        function OnCalcChannel(obj, ~, ~)
        % OnCalcChannel 通道运算对话框
            nDatasets = obj.Session.DatasetCount;
            if nDatasets == 0
                msgbox('请先导入数据', '提示');
                return;
            end

            % 构建通道列表
            channelList = {};
            channelMap = [];  % [datasetIdx, colIdx]
            for d = 1:nDatasets
                ds = obj.Session.GetDataset(d);
                dsName = obj.Session.GetDatasetName(d);
                for c = 1:ds.ColumnCount
                    channelList{end+1} = sprintf('%s > %s', dsName, ds.GetColumnName(c)); %#ok<AGROW>
                    channelMap(end+1, :) = [d, c]; %#ok<AGROW>
                end
            end

            if isempty(channelList)
                msgbox('无可用通道', '提示');
                return;
            end

            % 运算类型
            opTypes = {'A + B', 'A - B', 'A × B', 'A ÷ B', ...
                       'diff(A)', 'cumsum(A)', '|A|', 'A²', '√A', ...
                       'log₁₀(A)', 'detrend(A)', 'RMS(A)', 'smooth(A)'};
            opKeys  = {'add', 'sub', 'mul', 'div', ...
                       'diff', 'cumsum', 'abs', 'square', 'sqrt', ...
                       'log10', 'detrend', 'rms', 'smooth'};

            % 创建对话框
            dlg = figure('Name', '通道运算', 'NumberTitle', 'off', ...
                'MenuBar', 'none', 'ToolBar', 'none', ...
                'Position', [400 300 380 380], 'Resize', 'off');

            % 运算类型
            uicontrol(dlg, 'Style', 'text', 'String', '运算类型:', ...
                'Units', 'normalized', 'Position', [0.05 0.88 0.25 0.06], ...
                'HorizontalAlignment', 'left');
            opPopup = uicontrol(dlg, 'Style', 'popupmenu', 'String', opTypes, ...
                'Units', 'normalized', 'Position', [0.32 0.88 0.63 0.06], ...
                'Callback', @(s,e) updateOpType());

            % 通道A
            uicontrol(dlg, 'Style', 'text', 'String', '通道A:', ...
                'Units', 'normalized', 'Position', [0.05 0.78 0.25 0.06], ...
                'HorizontalAlignment', 'left');
            popupA = uicontrol(dlg, 'Style', 'popupmenu', 'String', channelList, ...
                'Units', 'normalized', 'Position', [0.32 0.78 0.63 0.06]);

            % 通道B
            uicontrol(dlg, 'Style', 'text', 'String', '通道B:', ...
                'Units', 'normalized', 'Position', [0.05 0.68 0.25 0.06], ...
                'HorizontalAlignment', 'left');
            popupB = uicontrol(dlg, 'Style', 'popupmenu', 'String', channelList, ...
                'Units', 'normalized', 'Position', [0.32 0.68 0.63 0.06], ...
                'Enable', 'off');

            % 通道A 范围（起点 + 长度）
            uicontrol(dlg, 'Style', 'text', 'String', '通道A:', ...
                'Units', 'normalized', 'Position', [0.05 0.56 0.15 0.06], ...
                'HorizontalAlignment', 'left');
            uicontrol(dlg, 'Style', 'text', 'String', '起点', ...
                'Units', 'normalized', 'Position', [0.2 0.56 0.1 0.06]);
            editA1 = uicontrol(dlg, 'Style', 'edit', 'String', '1', ...
                'Units', 'normalized', 'Position', [0.3 0.56 0.2 0.06]);
            uicontrol(dlg, 'Style', 'text', 'String', '长度', ...
                'Units', 'normalized', 'Position', [0.52 0.56 0.1 0.06]);
            editA2 = uicontrol(dlg, 'Style', 'edit', 'String', '', ...
                'Units', 'normalized', 'Position', [0.62 0.56 0.2 0.06]);

            % 通道B 范围（起点 + 长度）
            uicontrol(dlg, 'Style', 'text', 'String', '通道B:', ...
                'Units', 'normalized', 'Position', [0.05 0.46 0.15 0.06], ...
                'HorizontalAlignment', 'left');
            uicontrol(dlg, 'Style', 'text', 'String', '起点', ...
                'Units', 'normalized', 'Position', [0.2 0.46 0.1 0.06]);
            editB1 = uicontrol(dlg, 'Style', 'edit', 'String', '1', ...
                'Units', 'normalized', 'Position', [0.3 0.46 0.2 0.06], 'Enable', 'off');
            uicontrol(dlg, 'Style', 'text', 'String', '长度', ...
                'Units', 'normalized', 'Position', [0.52 0.46 0.1 0.06]);
            editB2 = uicontrol(dlg, 'Style', 'edit', 'String', '', ...
                'Units', 'normalized', 'Position', [0.62 0.46 0.2 0.06], 'Enable', 'off');

            % 窗口大小（smooth）
            uicontrol(dlg, 'Style', 'text', 'String', '窗口大小:', ...
                'Units', 'normalized', 'Position', [0.05 0.36 0.25 0.06], ...
                'HorizontalAlignment', 'left', 'Visible', 'off', 'Tag', 'smoothLabel');
            editWin = uicontrol(dlg, 'Style', 'edit', 'String', '10', ...
                'Units', 'normalized', 'Position', [0.32 0.36 0.3 0.06], ...
                'Visible', 'off', 'Tag', 'smoothEdit');

            % 结果名称
            uicontrol(dlg, 'Style', 'text', 'String', '结果名称:', ...
                'Units', 'normalized', 'Position', [0.05 0.26 0.25 0.06], ...
                'HorizontalAlignment', 'left');
            editName = uicontrol(dlg, 'Style', 'edit', 'String', '', ...
                'Units', 'normalized', 'Position', [0.32 0.26 0.63 0.06]);

            % 按钮
            uicontrol(dlg, 'Style', 'pushbutton', 'String', '确定', ...
                'Units', 'normalized', 'Position', [0.25 0.08 0.2 0.1], ...
                'Callback', @(s,e) doCalc());
            uicontrol(dlg, 'Style', 'pushbutton', 'String', '取消', ...
                'Units', 'normalized', 'Position', [0.55 0.08 0.2 0.1], ...
                'Callback', @(s,e) close(dlg));

            % 初始化
            updateOpType();

            function updateOpType()
                val = get(opPopup, 'Value');
                key = opKeys{val};
                isDual = any(strcmp(key, {'add','sub','mul','div'}));
                isSmooth = strcmp(key, 'smooth');

                if isDual
                    set(popupB, 'Enable', 'on');
                    set(editB1, 'Enable', 'on');
                    set(editB2, 'Enable', 'on');
                else
                    set(popupB, 'Enable', 'off');
                    set(editB1, 'Enable', 'off');
                    set(editB2, 'Enable', 'off');
                end

                % smooth 窗口控件
                allKids = allchild(dlg);
                for k = 1:length(allKids)
                    tg = get(allKids(k), 'Tag');
                    if strcmp(tg, 'smoothLabel') || strcmp(tg, 'smoothEdit')
                        if isSmooth
                            set(allKids(k), 'Visible', 'on');
                        else
                            set(allKids(k), 'Visible', 'off');
                        end
                    end
                end

                % 自动生成结果名称
                idxA = get(popupA, 'Value');
                nameA = channelList{idxA};
                nameA = strrep(nameA, ' > ', '_');
                if isDual
                    idxB = get(popupB, 'Value');
                    nameB = channelList{idxB};
                    nameB = strrep(nameB, ' > ', '_');
                    ops = {'+', '-', '×', '÷'};
                    defaultName = sprintf('%s%s%s', nameA, ops{val}, nameB);
                else
                    opNames = {'diff', 'cumsum', 'abs', 'sq', 'sqrt', 'log10', 'detrend', 'rms', 'smooth'};
                    defaultName = sprintf('%s(%s)', opNames{val}, nameA);
                end
                if length(defaultName) > 63
                    defaultName = defaultName(1:63);
                end
                set(editName, 'String', defaultName);

                % 更新范围默认值（起点=1, 长度=总行数）
                if idxA <= size(channelMap, 1)
                    dsA = obj.Session.GetDataset(channelMap(idxA, 1));
                    set(editA1, 'String', '1');
                    set(editA2, 'String', num2str(dsA.RowCount));
                end
                if isDual && idxB <= size(channelMap, 1)
                    dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                    set(editB1, 'String', '1');
                    set(editB2, 'String', num2str(dsB.RowCount));
                end
            end

            function doCalc()
                try
                    opVal = get(opPopup, 'Value');
                    key = opKeys{opVal};
                    isDual = any(strcmp(key, {'add','sub','mul','div'}));

                    idxA = get(popupA, 'Value');
                    dsIdxA = channelMap(idxA, 1);
                    colIdxA = channelMap(idxA, 2);
                    dsA = obj.Session.GetDataset(dsIdxA);
                    dataA = dsA.GetColumn(colIdxA);
                    srA = dsA.SampleRate;

                    % 通道A 范围（起点 + 长度）
                    a1 = round(str2double(get(editA1, 'String')));
                    aLen = round(str2double(get(editA2, 'String')));
                    if isnan(a1), a1 = 1; end
                    if isnan(aLen), aLen = size(dataA, 1); end
                    a1 = max(1, a1);
                    aLen = max(1, min(aLen, size(dataA, 1) - a1 + 1));
                    dataA = dataA(a1 : a1 + aLen - 1);

                    if isDual
                        idxB = get(popupB, 'Value');
                        dsIdxB = channelMap(idxB, 1);
                        colIdxB = channelMap(idxB, 2);
                        dsB = obj.Session.GetDataset(dsIdxB);
                        dataB = dsB.GetColumn(colIdxB);

                        b1 = round(str2double(get(editB1, 'String')));
                        bLen = round(str2double(get(editB2, 'String')));
                        if isnan(b1), b1 = 1; end
                        if isnan(bLen), bLen = size(dataB, 1); end
                        b1 = max(1, b1);
                        bLen = max(1, min(bLen, size(dataB, 1) - b1 + 1));
                        dataB = dataB(b1 : b1 + bLen - 1);

                        if length(dataA) ~= length(dataB)
                            errordlg(sprintf('窗口长度不一致: A=%d, B=%d', length(dataA), length(dataB)), '错误');
                            return;
                        end

                        switch key
                            case 'add', result = dataA + dataB;
                            case 'sub', result = dataA - dataB;
                            case 'mul', result = dataA .* dataB;
                            case 'div'
                                result = dataA ./ dataB;
                                result(dataB == 0) = NaN;
                        end
                    else
                        switch key
                            case 'diff',    result = diff(dataA) * srA;
                            case 'cumsum',  result = cumsum(dataA) / srA;
                            case 'abs',     result = abs(dataA);
                            case 'square',  result = dataA .^ 2;
                            case 'sqrt',    result = sqrt(abs(dataA));
                            case 'log10',   result = log10(abs(dataA) + eps);
                            case 'detrend', result = detrend(dataA);
                            case 'rms'
                                rmsVal = sqrt(mean(dataA.^2));
                                set(obj.StatusBar, 'String', sprintf('RMS = %.6g', rmsVal));
                                close(dlg);
                                return;
                            case 'smooth'
                                winStr = get(editWin, 'String');
                                winSize = round(str2double(winStr));
                                if isnan(winSize) || winSize < 2
                                    errordlg('窗口大小无效', '错误');
                                    return;
                                end
                                result = movmean(dataA, winSize);
                        end
                    end

                    resultName = strtrim(get(editName, 'String'));
                    if isempty(resultName)
                        resultName = sprintf('calc_%d', obj.Session.DatasetCount + 1);
                    end

                    % 保存为新数据集
                    tempDir = tempname;
                    mkdir(tempDir);
                    colNames = {resultName};
                    matPath = DataReaderFactory.SaveSubfolderResult(...
                        result, colNames, tempDir, resultName, 'calc', 'calc');
                    newDs = DataReaderFactory.LoadStandard(matPath);
                    obj.Session.AddDataset(newDs, resultName, matPath);

                    close(dlg);
                    fprintf('[Calc] %s → 新数据集 (%d×%d)\n', resultName, size(result,1), size(result,2));
                catch e
                    errordlg(sprintf('运算失败:\n%s', e.message), '错误');
                end
            end
        end

        function OnAddAxes(obj, ~, ~)
            try
                idx = obj.PlotCtrl.AddAxes();
                obj.Session.AddAxes();
                obj.CreateAxesTabBar(idx);
                obj.SetupAxesClickFocus(idx);
                obj.Session.SetFocusedAxes(idx);
            catch e
                errordlg(e.message, 'Error');
            end
        end

        function OnRemoveAxes(obj, ~, ~)
            nAxes = obj.PlotCtrl.GetAxesCount();
            if nAxes > 0
                obj.PlotCtrl.RemoveAxes(nAxes);
                obj.Session.RemoveAxes(nAxes);
                if ~isempty(obj.AxesTabBars)
                    for i = 1:length(obj.AxesTabBars{end})
                        if isvalid(obj.AxesTabBars{end}{i})
                            delete(obj.AxesTabBars{end}{i});
                        end
                    end
                    obj.AxesTabBars(end) = [];
                    obj.AxesAnalysisType(end) = [];
                end
            end
        end

        function OnLayoutVertical(obj, ~, ~)
            obj.PlotCtrl.Relayout('single');
        end

        function OnLayoutHorizontal(obj, ~, ~)
            obj.PlotCtrl.Relayout('dual');
        end

        function OnExportFigure(obj, ~, ~)
            nAxes = obj.PlotCtrl.GetAxesCount();
            if nAxes == 0
                return;
            end
            obj.PlotCtrl.ExportToFigure(1:nAxes);
        end

        function OnUndo(obj, ~, ~)
            if obj.SelectionMgr.HasHistory()
                obj.SelectionMgr.UndoSegment();
            end
        end

        function OnSelectionStartChanged(obj, src, ~)
            val = str2double(get(src, 'String'));
            if isnan(val) || val < 0
                return;
            end
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                startRow = max(1, round(val / ds.SampleTime));
                range = obj.Session.SelectionRange;
                obj.SelectionMgr.SetRange(startRow, range(2));
            end
        end

        function OnSelectionEndChanged(obj, src, ~)
            val = str2double(get(src, 'String'));
            if isnan(val) || val < 0
                return;
            end
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                endRow = min(ds.RowCount, round(val / ds.SampleTime));
                range = obj.Session.SelectionRange;
                obj.SelectionMgr.SetRange(range(1), endRow);
            end
        end

        function OnApplySelection(obj, ~, ~)
            startVal = str2double(get(obj.SelectionStartEdit, 'String'));
            endVal = str2double(get(obj.SelectionEndEdit, 'String'));
            if isnan(startVal) || isnan(endVal)
                return;
            end
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                startRow = max(1, round(startVal / ds.SampleTime));
                endRow = min(ds.RowCount, round(endVal / ds.SampleTime));
                obj.SelectionMgr.SetRange(startRow, endRow);
            end
        end

        function OnUndoSelection(obj, ~, ~)
            if obj.SelectionMgr.HasHistory()
                obj.SelectionMgr.UndoSegment();
            end
        end

        function UpdateStatusBar(obj)
            nDatasets = obj.Session.DatasetCount;
            if nDatasets == 0
                set(obj.StatusBar, 'String', 'Ready');
                return;
            end

            % 统计所有 axes 的通道总数
            totalChans = 0;
            for i = 1:length(obj.Session.AxesData_)
                chans = obj.Session.GetAxesChannels(i);
                totalChans = totalChans + length(chans);
            end

            range = obj.Session.SelectionRange;
            ds = obj.Session.GetDataset(1);
            sampleTime = ds.SampleTime;

            status = sprintf('Datasets: %d | Channels on axes: %d | Sel: %.3fs ~ %.3fs', ...
                nDatasets, totalChans, ...
                range(1)*sampleTime, range(2)*sampleTime);
            set(obj.StatusBar, 'String', status);
        end
    end
end
