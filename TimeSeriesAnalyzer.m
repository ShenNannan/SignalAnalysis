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
        AnalysisEngine_ AnalysisEngine

        % UI 控件
        ChannelPanel            % uipanel 通道列表容器
        ChannelControls   cell  % 通道控件 struct array: {handle, type, datasetIdx, colIdx}
        DatasetExpanded_  logical  % 每个数据集的展开状态
        SelectedDatasets_ logical  % 每个数据集的选中状态

        % 布局
        LeftPanel               % uipanel handle
        RightPanel              % uipanel handle
        AxesContainer           % uipanel handle

        % 归一化控件
        NormModeDropdown        % uicontrol popup 归一化模式选择
        NormButton              % uicontrol pushbutton 归一化按钮


    end

    methods
        function obj = TimeSeriesAnalyzer()
            obj.Session = SessionData(6);
            obj.ChannelControls = {};
            obj.DatasetExpanded_ = logical([]);
            obj.SelectedDatasets_ = logical([]);

            obj.BuildUI();
            obj.PlotCtrl = PlotController(obj.MainFigure, 6, obj.AxesContainer);
            obj.PlotCtrl.InitStatusBar();
            obj.AnalysisEngine_ = AnalysisEngine(obj.Session, obj.PlotCtrl);
            obj.PlotCtrl.SetupDataCursor();

            % 注册事件
            addlistener(obj.Session, 'DatasetsUpdated', @obj.OnDatasetsUpdated);
        end

        function BuildUI(obj)
            % 主图窗
            obj.MainFigure = figure( ...
                'Name', 'Signal Analysis - Time Series', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'none', ...
                'Position', [100 100 1200 700], ...
                'WindowButtonMotionFcn', @obj.OnMouseMotion, ...
                'CloseRequestFcn', @obj.OnClose);

            % 左面板（通道池）
            obj.LeftPanel = uipanel(obj.MainFigure, ...
                'Position', [0 0 0.2 1], ...
                'Title', '');

            % 通道列表区域（滚动面板）
            obj.ChannelPanel = uipanel(obj.LeftPanel, ...
                'Position', [0 0.12 1 0.88], ...
                'Title', '', ...
                'ButtonDownFcn', @(src, evt) obj.ClearDatasetSelection());

            % 底部按钮（3行布局）
            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Browse...', ...
                'Units', 'normalized', ...
                'Position', [0 0.12 1 0.04], ...
                'Callback', @obj.OnBrowseFile);

            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Import', ...
                'Units', 'normalized', ...
                'Position', [0 0.075 0.48 0.04], ...
                'Callback', @obj.OnImportFile);

            uicontrol(obj.LeftPanel, 'Style', 'pushbutton', ...
                'String', 'Clear All', ...
                'Units', 'normalized', ...
                'Position', [0.5 0.075 0.5 0.04], ...
                'Callback', @obj.OnClearAll);

            % 右面板（绘图区 + 选区 + 状态栏）
            obj.RightPanel = uipanel(obj.MainFigure, ...
                'Position', [0.2 0 0.8 1], ...
                'Title', '');

            % 工具栏：图窗操作 | 数据处理
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
                'Position', [0.22 0.96 0.08 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnExportFigure);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Clear Plot', ...
                'Units', 'normalized', ...
                'Position', [0.31 0.96 0.09 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnCloseAllFigures);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'FFT', ...
                'Units', 'normalized', ...
                'Position', [0.42 0.96 0.07 0.03], ...
                'FontSize', 8, ...
                'Callback', @(s,e) obj.OnAnalysisTabClicked(obj.Session.FocusedAxes, 'fft'));

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'PSD', ...
                'Units', 'normalized', ...
                'Position', [0.50 0.96 0.07 0.03], ...
                'FontSize', 8, ...
                'Callback', @(s,e) obj.OnAnalysisTabClicked(obj.Session.FocusedAxes, 'psd'));

            obj.NormModeDropdown = uicontrol(obj.RightPanel, 'Style', 'popupmenu', ...
                'String', {'None', 'Min-Max', 'Z-Score', 'Mean Zero'}, ...
                'Value', 1, ...
                'Units', 'normalized', ...
                'Position', [0.59 0.96 0.12 0.03], ...
                'FontSize', 8);

            obj.NormButton = uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Norm', ...
                'Units', 'normalized', ...
                'Position', [0.72 0.96 0.06 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnNormalizeAxes);

            uicontrol(obj.RightPanel, 'Style', 'pushbutton', ...
                'String', 'Calc', ...
                'Units', 'normalized', ...
                'Position', [0.79 0.96 0.06 0.03], ...
                'FontSize', 8, ...
                'Callback', @obj.OnCalcChannel);

            % Axes 容器
            obj.AxesContainer = uipanel(obj.RightPanel, ...
                'Position', [0 0 1 0.95], ...
                'Title', '', ...
                'BorderType', 'none');
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

            % 初始化展开状态（保留已有，新增默认折叠）
            if isempty(obj.DatasetExpanded_)
                obj.DatasetExpanded_ = false(1, nDatasets);
            elseif length(obj.DatasetExpanded_) < nDatasets
                obj.DatasetExpanded_(end+1:nDatasets) = false;
            elseif length(obj.DatasetExpanded_) > nDatasets
                obj.DatasetExpanded_ = obj.DatasetExpanded_(1:nDatasets);
            end
            % 同步选中状态
            if isempty(obj.SelectedDatasets_)
                obj.SelectedDatasets_ = false(1, nDatasets);
            elseif length(obj.SelectedDatasets_) < nDatasets
                obj.SelectedDatasets_(end+1:nDatasets) = false;
            elseif length(obj.SelectedDatasets_) > nDatasets
                obj.SelectedDatasets_ = obj.SelectedDatasets_(1:nDatasets);
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

                % 标题行（可点击展开/折叠，Ctrl+点击多选）
                if expanded
                    arrow = '▼';
                else
                    arrow = '▶';
                end
                headerText = sprintf('%s %s (%d)', arrow, displayName, nCols);
                selected = obj.SelectedDatasets_(d);
                if selected
                    bgColor = [0.85 0.92 1.0];  % 选中高亮
                else
                    bgColor = [0.94 0.94 0.94];  % 默认
                end
                h = uicontrol(obj.ChannelPanel, 'Style', 'pushbutton', ...
                    'String', headerText, ...
                    'Units', 'normalized', ...
                    'Position', [0 yPos 1 headerH], ...
                    'HorizontalAlignment', 'left', ...
                    'FontSize', 8, ...
                    'BackgroundColor', bgColor, ...
                    'TooltipString', dsName, ...
                    'Callback', @(src, evt) obj.OnDatasetHeaderClick(d));

                % 数据集标题右键菜单（作用于所有选中的数据集）
                cm = uicontextmenu(obj.MainFigure);
                uimenu(cm, 'Text', '设置采样率...', ...
                    'Callback', @(src, evt) obj.OnSetSampleRateForSelected(d));
                set(h, 'UIContextMenu', cm);

                obj.ChannelControls{end+1} = struct('handle', h, 'type', 'header', ...
                    'datasetIdx', d, 'colIdx', 0);
                yPos = yPos - headerH;

                % 展开时显示通道
                if expanded
                    for c = 1:nCols
                        % 检查是否在当前 axes 上 + 切片标记
                        sliceTag = '';
                        isChecked = false;
                        chansOnAxes = obj.Session.GetAxesChannels(obj.Session.FocusedAxes);
                        for sc = 1:length(chansOnAxes)
                            if chansOnAxes{sc}.DatasetIdx == d && chansOnAxes{sc}.ColIdx == c
                                isChecked = true;
                                if isfield(chansOnAxes{sc}, 'SliceRange')
                                    sr = chansOnAxes{sc}.SliceRange;
                                    totalN = length(chansOnAxes{sc}.Data);
                                    segLen = sr(2) - sr(1) + 1;
                                    if sr(1) > 1 || sr(2) < totalN || sr(2) > totalN
                                        sliceTag = sprintf(' [%d~%d L%d]', sr(1), sr(2), segLen);
                                    end
                                end
                                break;
                            end
                        end

                        label = sprintf('%d: %s (%d)%s', c, ds.GetColumnName(c), ds.RowCount, sliceTag);
                        h = uicontrol(obj.ChannelPanel, 'Style', 'checkbox', ...
                            'String', label, ...
                            'Units', 'normalized', ...
                            'Position', [0.05 yPos 0.93 lineH], ...
                            'Value', isChecked, ...
                            'FontSize', 8, ...
                            'Callback', @(src, evt) obj.OnChannelCheckbox(d, c, src));

                        % 注册右键菜单（重命名 + 切片）
                        cm = uicontextmenu(obj.MainFigure);
                        uimenu(cm, 'Text', '重命名...', ...
                            'Callback', @(src, evt) obj.OnRenameChannel(d, c));
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

        function SetupAxesContextMenu(obj, axesIdx)
        % SetupAxesContextMenu 为指定 axes 设置右键上下文菜单
            ax = obj.PlotCtrl.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            cm = uicontextmenu('Parent', obj.MainFigure);
            uimenu(cm, 'Text', '重置视图', ...
                'Callback', @(s,e) obj.ResetAxesView(axesIdx));
            uimenu(cm, 'Text', '清除数据提示', ...
                'Callback', @(s,e) delete(findall(ax, 'Type', 'hggroup')));
            uimenu(cm, 'Text', '网格开关', ...
                'Callback', @(s,e) obj.ToggleGrid(ax));
            uimenu(cm, 'Text', '导出到新窗口', ...
                'Callback', @(s,e) obj.PlotCtrl.ExportToFigure(axesIdx));
            ax.UIContextMenu = cm;
        end

        function ResetAxesView(obj, axesIdx)
        % ResetAxesView 重置指定 axes 的视图范围
            ax = obj.PlotCtrl.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end
            zoom(ax, 'reset');
        end

        function ToggleGrid(~, ax)
        % ToggleGrid 切换 axes 网格显示
            if isempty(ax) || ~isvalid(ax), return; end
            if strcmp(ax.XGrid, 'on')
                grid(ax, 'off');
            else
                grid(ax, 'on');
            end
        end

    end

    % Callbacks
    methods (Access = private)
        function OnClose(obj, ~, ~)
            % 关闭所有子窗口（频谱弹窗、导出窗口等）
            figs = findall(0, 'Type', 'figure');
            for i = 1:length(figs)
                if figs(i) ~= obj.MainFigure && isvalid(figs(i))
                    try delete(figs(i)); catch, end
                end
            end
            delete(obj.MainFigure);
        end

        function OnAxesClicked(obj, src, ~)
        % OnAxesClicked axes ButtonDownFcn：单击选中 axes
            sel = get(obj.MainFigure, 'SelectionType');
            if ~strcmp(sel, 'normal'), return; end

            for i = 1:obj.PlotCtrl.GetAxesCount()
                if obj.PlotCtrl.GetAxesHandle(i) == src
                    obj.Session.SetFocusedAxes(i);
                    obj.UpdateAxesHighlight();
                    return;
                end
            end
        end

        % ---- 游标与缩放 ----

        function OnMouseMotion(obj, ~, ~)
        % OnMouseMotion 鼠标移动：状态栏显示坐标

            try
                hitObj = hittest(obj.MainFigure);
                if isempty(hitObj) || ~isvalid(hitObj)
                    obj.PlotCtrl.ClearStatusBar();
                    return;
                end

                ax = ancestor(hitObj, 'axes');
                if isempty(ax)
                    obj.PlotCtrl.ClearStatusBar();
                    return;
                end

                % 找到对应 axes 索引
                axesIdx = 0;
                for i = 1:obj.PlotCtrl.GetAxesCount()
                    if obj.PlotCtrl.GetAxesHandle(i) == ax
                        axesIdx = i;
                        break;
                    end
                end
                if axesIdx == 0
                    obj.PlotCtrl.ClearStatusBar();
                    return;
                end

                pt = ax.CurrentPoint;
                obj.PlotCtrl.UpdateStatusBar(pt(1,1), pt(1,2), axesIdx);
            catch
                obj.PlotCtrl.ClearStatusBar();
            end
        end

        function UpdateAxesHighlight(obj)
        % UpdateAxesHighlight 高亮聚焦的 axes（粗边框）
            focused = obj.Session.FocusedAxes;
            for i = 1:obj.PlotCtrl.GetAxesCount()
                ax = obj.PlotCtrl.GetAxesHandle(i);
                if ~isempty(ax) && isvalid(ax)
                    if i == focused
                        set(ax, 'Box', 'on', 'LineWidth', 1.5);
                    else
                        set(ax, 'Box', 'off', 'LineWidth', 0.5);
                    end
                end
            end
        end

        function OnDatasetsUpdated(obj, ~, ~)
        % OnDatasetsUpdated 数据集变更
            obj.RebuildChannelList();
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
                    idx = obj.PlotCtrl.AddAxes(@obj.OnAxesClicked);
                    obj.Session.AddAxes();
                    obj.SetupAxesContextMenu(idx);
                end

                % 运行分析
                analysisType = obj.Session.GetAxesAnalysisType(axIdx);
                obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);
            else
                % 取消勾选：从 axes 移除该通道
                obj.Session.RemoveChannelFromAxes(axIdx, datasetIdx, colIdx);
                % 重绘
                analysisType = obj.Session.GetAxesAnalysisType(axIdx);
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
            obj.Session.SetAxesAnalysisType(axesIdx, analysisType);

            chans = obj.Session.GetAxesChannels(axesIdx);
            if isempty(chans), return; end

            if strcmpi(analysisType, 'fft') || strcmpi(analysisType, 'psd')
                obj.ShowSpectrumPopup(chans, analysisType);
            else
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

                % 统一导入（递归发现 + 逐目录处理）
                [results, ~] = DataReaderFactory.Import(rootDir);

                if isempty(results)
                    errordlg('未找到可导入的数据文件', '错误');
                    return;
                end

                % 将每个结果作为数据集加入 Session（跳过已导入的）
                existingPaths = obj.Session.DatasetPaths_;
                for i = 1:length(results)
                    if any(strcmp(results{i}.matPath, existingPaths))
                        continue;
                    end
                    ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                    obj.Session.AddDataset(ds, results{i}.name, results{i}.matPath);
                end

            catch e
                errordlg(sprintf('浏览文件夹失败:\n%s', e.message), '错误');
            end
        end

        function OnImportFile(obj, ~, ~)
            startPath = obj.Session.GetLastPath(1);
            if isempty(startPath), startPath = pwd; end

            [~, filePaths] = FileExplorer.SelectFiles(startPath, ...
                {'*.dat;*.csv;*.txt;*.xlsx', 'Data Files (*.dat;*.csv;*.txt;*.xlsx)'});

            if ~isempty(filePaths)
                try
                    outputDir = fileparts(filePaths{1});
                    fileStructs = cell(1, length(filePaths));
                    for k = 1:length(filePaths)
                        [~, fname] = fileparts(filePaths{k});
                        fileStructs{k} = struct('path', filePaths{k}, 'fname', fname);
                    end
                    results = DataReaderFactory.ProcessFileGroup(fileStructs, outputDir);
                    existingPaths = obj.Session.DatasetPaths_;
                    for i = 1:length(results)
                        if any(strcmp(results{i}.matPath, existingPaths))
                            continue;
                        end
                        ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                        obj.Session.AddDataset(ds, results{i}.name, results{i}.matPath);
                    end
                    obj.Session.SetLastPath(1, outputDir);
                catch e
                    errordlg(sprintf('导入失败:\n%s', e.message), '错误');
                end
            end
        end

        function OnClearAll(obj, ~, ~)
        % OnClearAll 重置全部（清空数据集和 axes）
            obj.Session.ClearAllDatasets();
            obj.PlotCtrl.ClearAll();
            obj.Session.SetFocusedAxes(1);
        end

        function OnDatasetHeaderClick(obj, dsIdx)
        % OnDatasetHeaderClick 左键点击数据集标题：展开/折叠，Ctrl+点击多选

            if dsIdx < 1 || dsIdx > length(obj.DatasetExpanded_), return; end

            % Ctrl+点击：切换选中状态
            fig = obj.MainFigure;
            ctrlDown = any(strcmp(get(fig, 'CurrentModifier'), 'control')) || ...
                       any(strcmp(get(fig, 'CurrentModifier'), 'command'));
            if ctrlDown
                obj.SelectedDatasets_(dsIdx) = ~obj.SelectedDatasets_(dsIdx);
                obj.RebuildChannelList();
                return;
            end

            % 普通点击：清除多选 + 展开/折叠
            if any(obj.SelectedDatasets_)
                obj.SelectedDatasets_(:) = false;
            end
            obj.DatasetExpanded_(dsIdx) = ~obj.DatasetExpanded_(dsIdx);
            obj.RebuildChannelList();
        end

        function ClearDatasetSelection(obj)
        % ClearDatasetSelection 清除所有数据集多选状态（点击空白处触发）
        % 如果有正在进行的内联重命名，先确认

            % 检查是否有活跃的 edit 控件（内联重命名中）
            for i = 1:length(obj.ChannelControls)
                cc = obj.ChannelControls{i};
                if strcmp(cc.type, 'edit') && isvalid(cc.handle)
                    obj.ApplyRename(cc.datasetIdx, cc.colIdx, get(cc.handle, 'String'));
                    return;  % ApplyRename 内部会 RebuildChannelList
                end
            end

            if any(obj.SelectedDatasets_)
                obj.SelectedDatasets_(:) = false;
                obj.RebuildChannelList();
            end
        end

        function OnSetSampleRateForSelected(obj, rightClickIdx)
        % OnSetSampleRateForSelected 对所有选中的数据集设置采样率
        % rightClickIdx - 右键点击的数据集索引，当无多选时作为回退目标

            selected = find(obj.SelectedDatasets_);
            if isempty(selected)
                selected = rightClickIdx;
            end

            % 弹窗输入采样率
            dsName = obj.Session.GetDatasetName(selected(1));
            if ~isscalar(selected)
                dsName = sprintf('%s 等 %d 个', dsName, length(selected));
            end
            newRate = obj.ShowSampleRateDialog(dsName);
            if isempty(newRate), return; end
            if isnan(newRate) || newRate <= 0
                errordlg('采样率必须为正数', '错误');
                return;
            end

            for i = 1:length(selected)
                idx = selected(i);
                obj.Session.UpdateSampleRate(idx, newRate);

                matPath = obj.Session.GetDatasetPath(idx);
                if ~isempty(matPath) && exist(matPath, 'file')
                    DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
                    jsonPath = strrep(matPath, '_standardized.mat', '_standardized_meta.json');
                    if exist(jsonPath, 'file')
                        try
                            meta = jsondecode(fileread(jsonPath));
                            meta.sample_rate = newRate;
                            DataReaderFactory.WriteJson(jsonPath, meta);
                        catch
                        end
                    end
                end
                dsName = obj.Session.GetDatasetName(idx);
                fprintf('[SampleRate] %s → %.4g Hz\n', dsName, newRate);
            end
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

            % 输入对话框：起点 + 长度（支持环形缓冲）
            ds = obj.Session.GetDataset(datasetIdx);
            colName = ds.GetColumnName(colIdx);
            [startRow, segLen] = obj.ShowSliceDialog(colName, totalRows, currentRange(1), currentLen);
            if isempty(startRow), return; end
            if isnan(startRow) || isnan(segLen) || startRow < 1 || segLen < 1
                errordlg('起点 ≥1, 长度 ≥1', '错误');
                return;
            end
            endRow = startRow + segLen - 1;
            if endRow > totalRows && segLen > startRow
                errordlg(sprintf('回绕时长度不能超过起点 %d', startRow), '错误');
                return;
            end

            obj.Session.SetChannelSlice(axIdx, chanIdx, startRow, endRow);

            % 重绘
            analysisType = obj.Session.GetAxesAnalysisType(axIdx);
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
            analysisType = obj.Session.GetAxesAnalysisType(axIdx);
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

            % 先用 none 模式重绘（隐藏 axes 避免闪烁）
            ax = obj.PlotCtrl.GetAxesHandle(axIdx);
            if ~isempty(ax) && isvalid(ax), ax.Visible = 'off'; end

            obj.Session.SetAxesNormMode(axIdx, 'none');
            obj.Session.SetAxesNormParams(axIdx, struct());
            analysisType = obj.Session.GetAxesAnalysisType(axIdx);
            obj.AnalysisEngine_.RunAnalysis(axIdx, analysisType);

            % 设置目标归一化模式并应用
            obj.Session.SetAxesNormMode(axIdx, normMode);
            if ~strcmpi(normMode, 'none')
                normParams = obj.ComputeNormParams(axIdx);
                obj.Session.SetAxesNormParams(axIdx, normParams);
                obj.PlotCtrl.NormalizeAxes(axIdx, normMode, normParams);
            end

            if ~isempty(ax) && isvalid(ax), ax.Visible = 'on'; end
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
                    defaultName = sprintf('%s(%s)', opNames{val - 4}, nameA);
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
                            case 'diff'
                                if isempty(srA)
                                    errordlg('请先设置采样率', '错误');
                                    return;
                                end
                                result = diff(dataA) * srA;
                            case 'cumsum'
                                if isempty(srA)
                                    errordlg('请先设置采样率', '错误');
                                    return;
                                end
                                result = cumsum(dataA) / srA;
                            case 'abs',     result = abs(dataA);
                            case 'square',  result = dataA .^ 2;
                            case 'sqrt',    result = sqrt(abs(dataA));
                            case 'log10',   result = log10(abs(dataA) + eps);
                            case 'detrend', result = detrend(dataA);
                            case 'rms'
                                rmsVal = sqrt(mean(dataA.^2));
                                msgbox(sprintf('RMS = %.6g', rmsVal), 'RMS');
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
                    matPath = DataReaderFactory.SaveStandard(...
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
                idx = obj.PlotCtrl.AddAxes(@obj.OnAxesClicked);
                obj.Session.AddAxes();
                obj.SetupAxesContextMenu(idx);
                obj.Session.SetFocusedAxes(idx);
                obj.UpdateAxesHighlight();
            catch e
                errordlg(e.message, '错误');
            end
        end

        function OnRemoveAxes(obj, ~, ~)
            nAxes = obj.PlotCtrl.GetAxesCount();
            if nAxes > 0
                obj.PlotCtrl.RemoveAxes(nAxes);
                obj.Session.RemoveAxes(nAxes);
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

        function OnCloseAllFigures(obj, ~, ~)
        % Clear Plot：清除绘图、取消所有通道勾选、清空 axes 通道数据
            obj.PlotCtrl.ClearAll();

            % 取消所有通道 checkbox
            for i = 1:length(obj.ChannelControls)
                cc = obj.ChannelControls{i};
                if strcmp(cc.type, 'checkbox') && isvalid(cc.handle)
                    set(cc.handle, 'Value', 0);
                end
            end

            % 清空 session 中所有 axes 的通道数据
            for a = 1:obj.Session.AxesSlotCount
                obj.Session.ClearAxes(a);
            end
        end
    end

    methods (Access = private)
        function normParams = ComputeNormParams(obj, axIdx)
        % ComputeNormParams 从当前 axes 视图计算归一化参数

            ax = obj.PlotCtrl.GetAxesHandle(axIdx);
            if isempty(ax) || ~isvalid(ax)
                normParams = struct();
                return;
            end

            xl = xlim(ax);
            refStart = max(1, round(xl(1)));
            refEnd = round(xl(2));

            chans = obj.Session.GetAxesChannels(axIdx);
            if isempty(chans)
                normParams = struct();
                return;
            end

            channelStats = {};
            for i = 1:length(chans)
                chan = chans{i};
                signal = chan.Data;
                totalLen = length(signal);

                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sliceStart = chan.SliceRange(1);
                else
                    sliceStart = 1;
                end

                refStartLocal = max(1, refStart - sliceStart + 1);
                refEndLocal = min(totalLen, refEnd - sliceStart + 1);
                if refStartLocal >= refEndLocal
                    refStartLocal = 1;
                    refEndLocal = totalLen;
                end

                refSig = signal(refStartLocal:refEndLocal);

                stats = struct();
                stats.minY = min(refSig);
                stats.maxY = max(refSig);
                stats.meanY = mean(refSig);
                stats.stdY = std(refSig);
                channelStats{end+1} = stats; %#ok<AGROW>
            end

            normParams = struct();
            normParams.refWindow = [refStart, refEnd];
            normParams.channelStats = channelStats;
        end

        function OnRenameChannel(obj, datasetIdx, colIdx)
        % OnRenameChannel 通道右键重命名 → 内联编辑

            % 找到对应的 checkbox handle
            chIdx = 0;
            for i = 1:length(obj.ChannelControls)
                cc = obj.ChannelControls{i};
                if strcmp(cc.type, 'checkbox') && cc.datasetIdx == datasetIdx && cc.colIdx == colIdx
                    chIdx = i;
                    break;
                end
            end
            if chIdx == 0, return; end

            chHandle = obj.ChannelControls{chIdx}.handle;
            if ~isvalid(chHandle), return; end

            % 取 checkbox 位置和当前列名
            pos = get(chHandle, 'Position');
            ds = obj.Session.GetDataset(datasetIdx);
            currentName = ds.GetColumnName(colIdx);

            % 用 edit 替换 checkbox
            delete(chHandle);
            editH = uicontrol(obj.ChannelPanel, 'Style', 'edit', ...
                'String', currentName, ...
                'Units', 'normalized', ...
                'Position', pos, ...
                'FontSize', 8, ...
                'HorizontalAlignment', 'left', ...
                'UserData', struct('datasetIdx', datasetIdx, 'colIdx', colIdx));

            % 更新 ChannelControls 记录
            obj.ChannelControls{chIdx} = struct('handle', editH, 'type', 'edit', ...
                'datasetIdx', datasetIdx, 'colIdx', colIdx);

            % 聚焦并全选
            uicontrol(editH);
            drawnow;

            % Enter 或失去焦点 → 确认；Escape → 取消
            set(editH, 'Callback', @(src, evt) obj.ApplyRename(datasetIdx, colIdx, get(src, 'String')));
            set(editH, 'KeyPressFcn', @(src, evt) obj.OnRenameKeyPress(src, evt, datasetIdx, colIdx));
        end

        function OnRenameKeyPress(obj, ~, evt, ~, ~)
        % OnRenameKeyPress 内联重命名键盘处理（仅 Escape 取消，Enter 由 Callback 处理）

            if strcmp(evt.Key, 'escape')
                obj.RebuildChannelList();
            end
        end

        function ApplyRename(obj, datasetIdx, colIdx, newName)
        % ApplyRename 应用重命名并同步磁盘

            newName = strtrim(newName);
            ds = obj.Session.GetDataset(datasetIdx);
            if isempty(newName) || strcmp(newName, ds.GetColumnName(colIdx))
                obj.RebuildChannelList();
                return;
            end

            % 1. 更新 Dataset 的 ColumnNames（内存）
            newNames = ds.ColumnNames;
            newNames{colIdx} = newName;
            newDs = ds.RebuildWithColumnNames(newNames);
            obj.Session.UpdateDataset(datasetIdx, newDs);

            % 2. 同步到磁盘文件
            matPath = obj.Session.GetDatasetMatPath(datasetIdx);
            if ~isempty(matPath)
                sa_column_names = newNames; %#ok<NASGU>
                save(matPath, 'sa_column_names', '-append');
                DataReaderFactory.UpdateColumnNamesInMeta(matPath, newNames);
                xlsxPath = strrep(matPath, '_standardized.mat', '_review.xlsx');
                try
                    DataReaderFactory.ExportToExcel(matPath, xlsxPath);
                catch
                end
            end

            % 3. 刷新显示（UpdateDataset 已触发 DatasetsUpdated → RebuildChannelList）
        end

        function ShowSpectrumPopup(obj, chans, analysisType)
        % ShowSpectrumPopup 弹窗显示原始信号 + 频谱分析
        %
        % 上面子图：原始时域信号
        % 下面子图：FFT 或 PSD（对数频率坐标）

            if isempty(chans), return; end

            colors = {'b', 'r', 'g', 'c', 'm', 'k'};

            fig = figure('Name', sprintf('Spectrum - %s', upper(analysisType)), ...
                'NumberTitle', 'off', 'Position', [200 150 900 700]);

            ax1 = subplot(2, 1, 1, 'Parent', fig);
            ax2 = subplot(2, 1, 2, 'Parent', fig);

            hold(ax1, 'on');
            hold(ax2, 'on');

            legendLabels1 = {};
            legendLabels2 = {};

            for c = 1:length(chans)
                chan = chans{c};
                signal = chan.Data;
                ds = obj.Session.GetDataset(chan.DatasetIdx);
                sampleRate = ds.SampleRate;

                % 采样率未设置时提示用户
                if isempty(sampleRate)
                    dsName = obj.Session.GetDatasetName(chan.DatasetIdx);
                    newRate = obj.ShowSampleRateDialog(dsName);
                    if isempty(newRate), continue; end
                    if isnan(newRate) || newRate <= 0
                        errordlg('采样率必须为正数', '错误');
                        continue;
                    end
                    obj.Session.UpdateSampleRate(chan.DatasetIdx, newRate);
                    matPath = obj.Session.GetDatasetPath(chan.DatasetIdx);
                    if ~isempty(matPath) && exist(matPath, 'file')
                        DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
                        jsonPath = strrep(matPath, '_standardized.mat', '_standardized_meta.json');
                        if exist(jsonPath, 'file')
                            try
                                meta = jsondecode(fileread(jsonPath));
                                meta.sample_rate = newRate;
                                DataReaderFactory.WriteJson(jsonPath, meta);
                            catch
                            end
                        end
                    end
                    sampleRate = newRate;
                end

                % 应用切片
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    startRow = chan.SliceRange(1);
                    endRow = chan.SliceRange(2);
                else
                    startRow = 1;
                    endRow = length(signal);
                end
                nSig = length(signal);
                startRow = max(1, min(startRow, nSig));
                if endRow <= nSig
                    sig = signal(startRow:endRow);
                else
                    tail = signal(startRow:nSig);
                    head = signal(1:endRow - nSig);
                    sig = [tail; head];
                end

                sampleIdx = (0:length(sig)-1)';
                colorIdx = mod(c-1, length(colors)) + 1;
                chanColor = colors{colorIdx};
                chanLabel = chan.Label;

                % 上面子图：原始时域信号
                plot(ax1, sampleIdx, sig, 'Color', chanColor, 'DisplayName', chanLabel);
                legendLabels1{end+1} = chanLabel;

                % 下面子图：频谱分析
                switch lower(analysisType)
                    case 'fft'
                        [P1, freq] = SignalProcessor.ComputeFFTSingleSided(sig, sampleRate);
                        % 跳过 DC(0 Hz)，自适应横轴
                        if freq(1) == 0
                            semilogx(ax2, freq(2:end), P1(2:end), 'Color', chanColor, 'DisplayName', chanLabel);
                        else
                            semilogx(ax2, freq, P1, 'Color', chanColor, 'DisplayName', chanLabel);
                        end
                        legendLabels2{end+1} = chanLabel;

                    case 'psd'
                        [cumRms, freq, totalRms] = SignalProcessor.ComputeCumulativeRMS(sig, sampleRate);
                        label = sprintf('%s (RMS=%.4f)', chanLabel, totalRms);
                        % 跳过 DC(0 Hz)，自适应横轴
                        if freq(1) == 0
                            semilogx(ax2, freq(2:end), cumRms(2:end), 'Color', chanColor, 'DisplayName', label);
                        else
                            semilogx(ax2, freq, cumRms, 'Color', chanColor, 'DisplayName', label);
                        end
                        legendLabels2{end+1} = label;
                end
            end

            hold(ax1, 'off');
            hold(ax2, 'off');

            xlabel(ax1, 'Sample Index');
            ylabel(ax1, 'Amplitude');
            title(ax1, 'Time Domain Signal');
            grid(ax1, 'on');
            if ~isempty(legendLabels1)
                legend(ax1, legendLabels1{:}, 'Location', 'best', 'Interpreter', 'none');
            end

            xlabel(ax2, 'Frequency (Hz)');
            switch lower(analysisType)
                case 'fft'
                    ylabel(ax2, 'Amplitude');
                    title(ax2, 'FFT Single-Sided Amplitude Spectrum');
                case 'psd'
                    ylabel(ax2, 'Cumulative RMS');
                    title(ax2, 'Cumulative RMS (from PSD)');
            end
            grid(ax2, 'on');
            set(ax2, 'XScale', 'log');
            if ~isempty(legendLabels2)
                legend(ax2, legendLabels2{:}, 'Location', 'best', 'Interpreter', 'none');
            end
        end
    end
end
