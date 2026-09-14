classdef TimeSeriesView < handle
% TimeSeriesView - 时域分析视图（哑终端）
%
% 只做控件装配、动态 uiaxes 管理（1-6 个，single/dual 布局）、渲染与事件广播，
% 零业务逻辑。状态栏为 app 级共享（uilabel），本视图不自建。
% 布局：左（通道 uitable + Browse/Import/Clear All）| 右（工具栏 + 动态 uiaxes 区）

    properties (SetAccess = private)
        Grid_           % 顶层 uigridlayout
        ChannelTable    % uitable（logical 勾选列 + 通道 + 数据集）
        AxesGrid        % uigridlayout 承载动态 uiaxes
        AxesHandles_    % cell，uiaxes handles
        AxesCount_      % double 当前 axes 数量
        LayoutMode_     % char 'single' | 'dual'
        FocusedAxes_    % double 当前聚焦 axes 索引
        SpectrumDropdown
        NormDropdown    % uidropdown 归一化模式
        LoadingDlg_     % uiprogressdlg
        CursorMgr_      % struct 游标管理器 .Lines{axIdx}, .InfoLabel, .Fig
    end

    properties (Access = private)
        ChannelRows_    % struct array：isParent/parentIdx/datasetIdx/colIdx/label/datasetName/checked
        ExpandedSets_   % containers.Map: datasetIdx → logical（展开状态）
        VisibleRowMap_  % 可见行号 → ChannelRows_ 索引映射
        Highlighting_   % logical 标志：防止程序设置 Selection 时触发 OnChannelSelect
        Rebuilding_     % logical 标志：防止 SetChannelTable 重建时触发 OnChannelSelect
        Renaming_       % logical 标志：重命名期间禁用展开/折叠
        RenameOriginal_ % char 重命名前的原始名称（用于判断是否变化）
        LastClickedRow_ % double 最近左键点击的行号（供右键菜单使用）
        MenuSetXAxis_    % uimenu handle: 设为横轴
        MenuClearXAxis_  % uimenu handle: 恢复默认横轴
        MenuSetRightY_   % uimenu handle: 设为右Y轴
        MenuClearRightY_ % uimenu handle: 恢复默认Y轴
        CurXChannel_     % 当前聚焦 axes 的横轴引用 [datasetIdx, colIdx] 或 []
        CurRightYChannel_ % 当前聚焦 axes 的右Y轴引用 [datasetIdx, colIdx] 或 []
        AxesXChannelMap_  % 每个 axes 的横轴引用 cell array，用于 linkaxes 分组
    end

    events
        BrowseClicked
        ImportButtonClicked
        ClearAllClicked
        ChannelCheckChanged     % 载荷 struct('datasetIdx',..,'colIdx',..,'checked',..)；colIdx=0 表示整个数据集
        AxesAddClicked
        AxesRemoveClicked
        LayoutChanged           % 载荷 struct('mode',..)
        ExportClicked
        ExportExcelClicked      % 载荷 struct('datasetIdx',..)
        SetSampleRateClicked    % 载荷 struct('datasetIdx',..)
        ClearPlotClicked
        SpectrumClicked
        CursorMotion            % 载荷 struct('axesIdx', 'x')
        NormClicked             % 载荷 struct('mode',..)
        CalcClicked
        AxesClicked             % 载荷 struct('axesIdx',..,'x',..,'y',..)
        RenameChannelClicked    % 载荷 struct('datasetIdx',..,'colIdx',..)
        InlineRenameChannel     % 载荷 struct('datasetIdx',..,'colIdx',..,'newName',..)
        InlineRenameDataset     % 载荷 struct('datasetIdx',..,'newName',..)

        SliceDialogClicked      % 载荷 struct('datasetIdx',..,'colIdx',..)
        SliceResetClicked       % 载荷 struct('datasetIdx',..,'colIdx',..)
        SetXAxisClicked         % 载荷 struct('datasetIdx',..,'colIdx',..)
        ClearXAxisClicked       % 载荷 struct('axesIdx',..)
        SetRightYAxisClicked    % 载荷 struct('datasetIdx',..,'colIdx',..)
        ClearRightYAxisClicked  % 载荷 struct('axesIdx',..)
    end

    methods
        function obj = TimeSeriesView(parent)
            obj.Grid_ = uigridlayout(parent, [1 2], ...
                'ColumnWidth', {'22x', '78x'}, ...
                'Padding', [6 6 6 6], ...
                'ColumnSpacing', 6);

            obj.AxesHandles_ = {};
            obj.AxesCount_ = 0;
            obj.LayoutMode_ = 'single';
            obj.FocusedAxes_ = 1;
            obj.ChannelRows_ = struct([]);
            obj.ExpandedSets_ = containers.Map('KeyType', 'double', 'ValueType', 'logical');
            obj.VisibleRowMap_ = [];
            obj.Highlighting_ = false;
            obj.Rebuilding_ = false;
            obj.Renaming_ = false;
            obj.RenameOriginal_ = '';
            obj.LastClickedRow_ = 0;
            obj.LoadingDlg_ = [];
            obj.CurXChannel_ = [];
            obj.CurRightYChannel_ = [];
            obj.AxesXChannelMap_ = {};

            obj.BuildChannelPanel();
            obj.BuildPlotPanel();
            obj.AddAxesInternal();
        end

        % ---- 通道表 ----

        function SetChannelTable(obj, rows)
        % SetChannelTable 填充通道表（折叠/展开模式）
        % rows 字段：isParent, parentIdx, datasetIdx, colIdx, label, datasetName, checked
        % 默认折叠：只显示数据集名行；点击展开显示通道
            obj.ChannelRows_ = rows;
            n = numel(rows);

            % 同步展开状态：新数据集默认折叠
            allDs = unique(arrayfun(@(r) r.datasetIdx, rows));
            for k = 1:numel(allDs)
                if ~obj.ExpandedSets_.isKey(allDs(k))
                    obj.ExpandedSets_(allDs(k)) = false;
                end
            end

            % 构建可见行
            checked = {};
            names = {};
            visMap = [];
            for i = 1:n
                r = rows(i);
                if r.isParent
                    checked{end+1} = r.checked; %#ok<AGROW>
                    dsIdx = r.datasetIdx;
                    names{end+1} = r.label; %#ok<AGROW>
                    visMap(end+1) = i; %#ok<AGROW>
                else
                    pIdx = r.parentIdx;
                    if pIdx > 0 && rows(pIdx).isParent
                        dsIdx = rows(pIdx).datasetIdx;
                        if obj.ExpandedSets_.isKey(dsIdx) && obj.ExpandedSets_(dsIdx)
                            checked{end+1} = r.checked; %#ok<AGROW>
                            names{end+1} = ['    ' r.label]; %#ok<AGROW>
                            visMap(end+1) = i; %#ok<AGROW>
                        end
                    end
                end
            end
            obj.VisibleRowMap_ = visMap;

            obj.Rebuilding_ = true;
            if isempty(checked)
                obj.ChannelTable.Data = table(logical([]), cell(0,1), ...
                    'VariableNames', {'选择', '数据集'});
            else
                obj.ChannelTable.Data = table([checked{:}]', names(:), ...
                    'VariableNames', {'选择', '数据集'});
            end
            obj.Rebuilding_ = false;
        end

        function rows = GetChannelRows(obj)
            rows = obj.ChannelRows_;
        end

        % ---- axes 管理 ----

        function count = GetAxesCount(obj)
            count = obj.AxesCount_;
        end

        function ax = GetAxes(obj, axesIdx)
            if axesIdx >= 1 && axesIdx <= numel(obj.AxesHandles_)
                ax = obj.AxesHandles_{axesIdx};
            else
                ax = [];
            end
        end

        function idx = GetFocusedAxes(obj)
            idx = obj.FocusedAxes_;
        end

        function SetLayout(obj, mode)
        % SetLayout 切换布局 'single' | 'dual'
            if ~any(strcmpi(mode, {'single', 'dual'}))
                return;
            end
            obj.LayoutMode_ = lower(mode);
            obj.RelayoutGrid();
        end

        function ClearAxes(obj, axesIdx)
            ax = obj.GetAxes(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                legend(ax, 'off');
                cla(ax);
            end
        end

        function ClearAllAxes(obj)
            for i = 1:obj.AxesCount_
                obj.ClearAxes(i);
            end
            obj.AxesXChannelMap_ = {};
            obj.CurXChannel_ = [];
            obj.CurRightYChannel_ = [];
        end

        % ---- 渲染接口 ----

        function RenderWaveform(obj, axesIdx, xCell, yCell, labels, colors, rightYData)
        % RenderWaveform 在指定 axes 叠画多条通道（支持双Y轴）
        % rightYData: [] 无右Y，或 struct('x',..,'y',..,'label',..,'color',..)
            if nargin < 7
                rightYData = [];
            end
            ax = obj.GetAxes(axesIdx);
            if isempty(ax) || ~isvalid(ax)
                return;
            end

            hasRightY = isstruct(rightYData) && isfield(rightYData, 'x') && ~isempty(rightYData.x);

            % 保存交互属性（cla('reset') 会清除它们）
            savedButtonDownFcn = ax.ButtonDownFcn;

            % 彻底重置 axes（退出 yyaxis 结构 + 清除所有子对象）
            cla(ax, 'reset');

            % 恢复交互属性
            ax.ButtonDownFcn = savedButtonDownFcn;
            ax.LineStyleOrder = '-';
            ax.LineStyleOrderIndex = 1;
            ax.ColorOrderIndex = 1;

            if hasRightY
                % ---- 双Y模式：用 yyaxis ----
                yyaxis(ax, 'left');
                hold(ax, 'on');
                allLines = gobjects(0);
                for c = 1:numel(yCell)
                    [~, shortLabel] = strtok(labels{c}, '/');
                    if isempty(shortLabel), displayName = labels{c};
                    else, displayName = strtrim(shortLabel(2:end)); end
                    h = plot(ax, xCell{c}, yCell{c}, 'Color', colors{c}, 'LineWidth', 1, 'LineStyle', '-', 'DisplayName', displayName, 'Tag', 'leftY');
                    allLines(end+1) = h;
                end
                hold(ax, 'off');

                yyaxis(ax, 'right');
                hold(ax, 'on');
                for c = 1:numel(rightYData.x)
                    h = plot(ax, rightYData.x{c}, rightYData.y{c}, ...
                        'Color', rightYData.colors{c}, 'LineWidth', 1, 'LineStyle', '--', ...
                        'DisplayName', rightYData.labels{c}, 'Tag', 'rightY');
                    allLines(end+1) = h;
                end
                hold(ax, 'off');

                yyaxis(ax, 'left');  % 固定活动侧
            else
                % ---- 普通模式 ----
                hold(ax, 'on');
                allLines = gobjects(0);
                for c = 1:numel(yCell)
                    [~, shortLabel] = strtok(labels{c}, '/');
                    if isempty(shortLabel), displayName = labels{c};
                    else, displayName = strtrim(shortLabel(2:end)); end
                    h = plot(ax, xCell{c}, yCell{c}, 'Color', colors{c}, 'LineWidth', 1, 'LineStyle', '-', 'DisplayName', displayName);
                    allLines(end+1) = h;
                end
                hold(ax, 'off');
            end

            grid(ax, 'on');

            if numel(allLines) >= 2
                legend(ax, allLines, 'Interpreter', 'none', 'Location', 'northwest');
            elseif numel(allLines) == 1
                legend(ax, 'off');
            end
        end

        function RefreshLegends(obj)
        % RefreshLegends 为全部 axes 重建 legend（页签切换可见后由 app 调用）
            obj.CleanupBrokenLegends();
            for i = 1:obj.AxesCount_
                obj.RefreshLegendFor(obj.AxesHandles_{i});
            end
        end

        function UpdateAxisChannelState(obj, axIdx, xDsIdx, xColIdx, rightYList)
        % UpdateAxisChannelState 更新当前 axes 的横轴/右Y轴引用（供 Presenter 调用）
        %   rightYList: cell array of [datasetIdx, colIdx]，支持多个右Y通道
            if ~isempty(xDsIdx)
                obj.CurXChannel_ = [xDsIdx, xColIdx];
            else
                obj.CurXChannel_ = [];
            end
            obj.CurRightYChannel_ = rightYList;  % cell array of [dsIdx, colIdx]
            % 更新每轴 X 通道映射（用于 linkaxes 分组）
            while length(obj.AxesXChannelMap_) < axIdx
                obj.AxesXChannelMap_{end+1} = [];
            end
            obj.AxesXChannelMap_{axIdx} = obj.CurXChannel_;
        end

        function ShowLoading(obj, msg)
            if nargin < 2
                msg = '处理中...';
            end
            obj.LoadingDlg_ = uiprogressdlg(ancestor(obj.Grid_, 'figure'), ...
                'Title', '请稍候', 'Message', msg, 'Indeterminate', 'on');
            drawnow;
        end

        function CloseLoading(obj)
            if ~isempty(obj.LoadingDlg_) && isvalid(obj.LoadingDlg_)
                close(obj.LoadingDlg_);
            end
            obj.LoadingDlg_ = [];
        end

        function ShowError(obj, msg)
            uialert(ancestor(obj.Grid_, 'figure'), msg, '错误', 'Icon', 'error');
        end

        function ShowInfo(obj, msg)
            uialert(ancestor(obj.Grid_, 'figure'), msg, '提示', 'Icon', 'success');
        end

        % ---- 同步游标卡尺 ----

        function mgr = InitCursorManager(obj, infoLabel)
        % InitCursorManager 创建同步游标 xline（仅为已存在的 axes）
            lineOpts = {'Color', [0.85 0.32 0.09], 'LineWidth', 1.2, ...
                        'LineStyle', '-', 'HitTest', 'off', ...
                        'PickableParts', 'none', 'Visible', 'off'};
            lines = cell(1, obj.AxesCount_);
            for i = 1:obj.AxesCount_
                lines{i} = xline(obj.AxesHandles_{i}, 0, lineOpts{:});
            end
            if nargin < 2 || isempty(infoLabel)
                mgr = struct('Lines', {lines});
            else
                mgr = struct('Lines', {lines}, 'InfoLabel', infoLabel);
            end
            obj.CursorMgr_ = mgr;
        end

        function UpdateCursorPosition(obj, axesIdx, xVal, groupAxes)
        % UpdateCursorPosition 更新游标位置，仅显示同组 axes
            if isempty(obj.CursorMgr_), return; end
            lines = obj.CursorMgr_.Lines;
            for i = 1:numel(lines)
                if ismember(i, groupAxes)
                    lines{i}.Value = xVal;
                    lines{i}.Visible = 'on';
                else
                    lines{i}.Visible = 'off';
                end
            end
        end

        function HideCursor(obj)
        % HideCursor 隐藏所有游标线
            if isempty(obj.CursorMgr_), return; end
            lines = obj.CursorMgr_.Lines;
            for i = 1:numel(lines)
                lines{i}.Visible = 'off';
            end
            if isfield(obj.CursorMgr_, 'InfoLabel') && ~isempty(obj.CursorMgr_.InfoLabel)
                obj.CursorMgr_.InfoLabel.Text = '游标: --';
            end
        end

        function RegisterCursorMotionFcn(obj)
        % RegisterCursorMotionFcn 注册全局鼠标移动回调（保留已有回调）
            fig = ancestor(obj.Grid_, 'figure');
            if isempty(fig), return; end
            oldFcn = fig.WindowButtonMotionFcn;
            fig.WindowButtonMotionFcn = @(s, e) obj.onCursorMotionWrapper(oldFcn);
        end
    end

    methods (Access = private)
        function BuildChannelPanel(obj)
            left = uigridlayout(obj.Grid_, [2 1], ...
                'RowHeight', {'1x', 30}, ...
                'RowSpacing', 4);
            left.Layout.Column = 1;

            obj.ChannelTable = uitable(left, ...
                'ColumnName', {'选择', '数据集'}, ...
                'ColumnEditable', [true false], ...
                'ColumnWidth', {38, '1x'});
            obj.ChannelTable.Layout.Row = 1;
            obj.ChannelTable.Data = table(false(0, 1), cell(0, 1), ...
                'VariableNames', {'选择', '数据集'});
            obj.ChannelTable.CellEditCallback = @(s, e) obj.OnChannelEdit(e);
            obj.ChannelTable.CellSelectionCallback = @(s, e) obj.OnChannelSelect(e);

            cm = uicontextmenu(ancestor(left, 'figure'));
            uimenu(cm, 'Text', '重命名', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextRename());
            uimenu(cm, 'Text', '设置采样频率...', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('setSampleRate'));
            uimenu(cm, 'Text', '导出 Excel', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextAction('exportExcel'));
            uimenu(cm, 'Text', '设置切片范围...', 'Separator', 'on', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('slice'));
            uimenu(cm, 'Text', '切片重置', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('sliceReset'));
            obj.MenuSetXAxis_ = uimenu(cm, 'Text', '设为横轴', 'Separator', 'on', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('setXAxis'));
            obj.MenuClearXAxis_ = uimenu(cm, 'Text', '恢复默认横轴', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('clearXAxis'), ...
                'Enable', 'off');
            obj.MenuSetRightY_ = uimenu(cm, 'Text', '设为右 Y 轴', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('setRightY'));
            obj.MenuClearRightY_ = uimenu(cm, 'Text', '恢复默认 Y 轴', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextChannelAction('clearRightY'), ...
                'Enable', 'off');
            obj.ChannelTable.ContextMenu = cm;
            cm.ContextMenuOpeningFcn = @(s, e) obj.OnContextMenuOpening();

            btns = uigridlayout(left, [1 3], ...
                'ColumnWidth', {'1x', '1x', '1x'}, ...
                'ColumnSpacing', 4, ...
                'Padding', [2 2 2 2]);
            btns.Layout.Row = 2;
            uibutton(btns, 'push', 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'BrowseClicked'));
            uibutton(btns, 'push', 'Text', 'Import', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ImportButtonClicked'));
            uibutton(btns, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ClearAllClicked'));
        end

        function BuildPlotPanel(obj)
            right = uigridlayout(obj.Grid_, [2 1], ...
                'RowHeight', {36, '1x'}, ...
                'RowSpacing', 4);
            right.Layout.Column = 2;

            obj.BuildToolbar(right);

            obj.AxesGrid = uigridlayout(right, [1 1], ...
                'RowHeight', {'1x'}, ...
                'ColumnWidth', {'1x'}, ...
                'RowSpacing', 4, ...
                'ColumnSpacing', 4);
            obj.AxesGrid.Layout.Row = 2;
        end

        function BuildToolbar(obj, parent)
            sq = 28;  % 小方按钮边长
            tb = uigridlayout(parent, [1 12], ...
                'ColumnWidth', {sq, sq, sq, sq, 60, 48, '1x', 80, 44, 90, 44, 44}, ...
                'RowHeight', {sq}, ...
                'ColumnSpacing', 4, ...
                'Padding', [4 4 4 4]);
            tb.Layout.Row = 1;

            % --- 左侧：axes 布局 + 图形操作（等间距排列）---
            uibutton(tb, 'push', 'Text', '+', 'FontWeight', 'bold', ...
                'FontSize', 14, ...
                'ButtonPushedFcn', @(s, e) obj.OnAddAxesClicked());
            uibutton(tb, 'push', 'Text', char(8722), 'FontSize', 14, ...
                'ButtonPushedFcn', @(s, e) obj.OnRemoveAxesClicked());
            uibutton(tb, 'push', 'Text', '||', ...
                'ButtonPushedFcn', @(s, e) obj.OnLayoutClicked('single'));
            uibutton(tb, 'push', 'Text', '=', ...
                'ButtonPushedFcn', @(s, e) obj.OnLayoutClicked('dual'));
            uibutton(tb, 'push', 'Text', 'Export', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ExportClicked'));
            uibutton(tb, 'push', 'Text', 'Clear', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ClearPlotClicked'));
            % 弹性间隔（推挤右侧数据操作按钮右对齐）
            uipanel(tb, 'Visible', 'off', 'BorderType', 'none');
            % --- 右侧：数据操作（以 Calc 为右起点）---
            obj.SpectrumDropdown = uidropdown(tb, ...
                'Items', {'FFT', 'PSD'}, ...
                'Value', 'FFT', 'Tooltip', '选择频谱分析模式');
            uibutton(tb, 'push', 'Text', '频谱', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'SpectrumClicked'));
            obj.NormDropdown = uidropdown(tb, ...
                'Items', {'None', 'Min-Max', 'Z-Score', 'Mean Zero'}, ...
                'Value', 'None');
            uibutton(tb, 'push', 'Text', 'Norm', ...
                'ButtonPushedFcn', @(s, e) obj.OnNormClicked());
            uibutton(tb, 'push', 'Text', 'Calc', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'CalcClicked'));
        end

        % ---- axes 内部管理 ----

        function OnAddAxesClicked(obj)
            if obj.AxesCount_ >= 6
                obj.ShowError('最多支持 6 个 axes');
                return;
            end
            obj.AddAxesInternal();
            notify(obj, 'AxesAddClicked');
        end

        function AddAxesInternal(obj)
            if obj.AxesCount_ >= 6
                return;
            end
            obj.AxesCount_ = obj.AxesCount_ + 1;
            ax = uiaxes(obj.AxesGrid);
            grid(ax, 'on');
            ylabel(ax, 'Amplitude');
            idx = obj.AxesCount_;
            ax.ButtonDownFcn = @(s, e) obj.OnAxesButtonDown(idx, e);
            obj.AxesHandles_{end+1} = ax;
            % 为新 axes 添加游标线
            if ~isempty(obj.CursorMgr_) && isfield(obj.CursorMgr_, 'Lines')
                obj.CursorMgr_.Lines{end+1} = xline(ax, 0, ...
                    'Color', [0.85 0.32 0.09], 'LineWidth', 1.2, ...
                    'LineStyle', '-', 'HitTest', 'off', ...
                    'PickableParts', 'none', 'Visible', 'off');
            end
            obj.RelayoutGrid();
            obj.LinkXAxes();
        end

        function OnRemoveAxesClicked(obj)
            if obj.AxesCount_ <= 1
                obj.ShowError('至少保留 1 个 axes');
                return;
            end
            obj.AxesCount_ = obj.AxesCount_ - 1;
            delete(obj.AxesHandles_{end});
            obj.AxesHandles_(end) = [];
            if ~isempty(obj.AxesXChannelMap_) && length(obj.AxesXChannelMap_) >= obj.AxesCount_ + 1
                obj.AxesXChannelMap_(end) = [];
            end
            % 移除对应的游标线
            if ~isempty(obj.CursorMgr_) && isfield(obj.CursorMgr_, 'Lines') ...
                    && numel(obj.CursorMgr_.Lines) > obj.AxesCount_
                obj.CursorMgr_.Lines(end) = [];
            end
            obj.FocusedAxes_ = min(obj.FocusedAxes_, obj.AxesCount_);
            obj.RelayoutGrid();
            obj.LinkXAxes();
            notify(obj, 'AxesRemoveClicked');
        end

        function OnLayoutClicked(obj, mode)
            if strcmpi(obj.LayoutMode_, mode)
                return;
            end
            obj.SetLayout(mode);
            notify(obj, 'LayoutChanged', AppEventData(struct('mode', mode)));
        end

        function RelayoutGrid(obj)
            n = obj.AxesCount_;
            if n == 0
                return;
            end
            if strcmp(obj.LayoutMode_, 'dual')
                nCols = 2;
            else
                nCols = 1;
            end
            nRows = ceil(n / nCols);
            set(obj.AxesGrid, ...
                'RowHeight', repmat({'1x'}, 1, nRows), ...
                'ColumnWidth', repmat({'1x'}, 1, nCols));
            for i = 1:n
                col = mod(i - 1, nCols) + 1;
                row = ceil(i / nCols);
                obj.AxesHandles_{i}.Layout.Row = row;
                obj.AxesHandles_{i}.Layout.Column = col;
                if row == nRows
                    xlabel(obj.AxesHandles_{i}, 'Sample Index');
                else
                    xlabel(obj.AxesHandles_{i}, '');
                end
            end
        end

        function LinkXAxes(obj)
        % LinkXAxes 仅链接使用相同自定义横轴的 axes（默认索引的 axes 不互相链接）
            % 先清除所有旧链接
            for i = 1:numel(obj.AxesHandles_)
                a = obj.AxesHandles_{i};
                if ~isempty(a) && isvalid(a)
                    linkaxes(a, 'off');
                end
            end
            % 收集有效 axes 及其 X 通道引用
            validHandles = {};
            validXRef = {};
            for i = 1:numel(obj.AxesHandles_)
                a = obj.AxesHandles_{i};
                if ~isempty(a) && isvalid(a)
                    validHandles{end+1} = a;
                    if i <= length(obj.AxesXChannelMap_) && ~isempty(obj.AxesXChannelMap_{i})
                        validXRef{end+1} = obj.AxesXChannelMap_{i};
                    else
                        validXRef{end+1} = [];
                    end
                end
            end
            if numel(validHandles) < 2
                return;
            end
            % 按自定义X通道分组（默认索引的不参与链接）
            groups = containers.Map('KeyType', 'char', 'ValueType', 'any');
            for i = 1:numel(validHandles)
                ref = validXRef{i};
                if isempty(ref)
                    continue; % 默认索引，不链接
                end
                key = sprintf('%d_%d', ref(1), ref(2));
                if groups.isKey(key)
                    groups(key) = [groups(key), validHandles(i)];
                else
                    groups(key) = validHandles(i);
                end
            end
            % 每组内链接
            keys = groups.keys();
            for k = 1:numel(keys)
                grp = groups(keys{k});
                if numel(grp) >= 2
                    linkaxes([grp{:}], 'x');
                end
            end
        end

        function OnAxesButtonDown(obj, axesIdx, e)
            obj.FocusedAxes_ = axesIdx;
            obj.UpdateAxesHighlight();
            x = NaN;
            y = NaN;
            if ~isempty(e) && isprop(e, 'IntersectionPoint')
                x = e.IntersectionPoint(1);
                y = e.IntersectionPoint(2);
            end
            notify(obj, 'AxesClicked', AppEventData(struct('axesIdx', axesIdx, 'x', x, 'y', y)));
        end

        function UpdateAxesHighlight(obj)
            for i = 1:obj.AxesCount_
                ax = obj.AxesHandles_{i};
                if i == obj.FocusedAxes_
                    ax.Box = 'on';
                    ax.LineWidth = 1.5;
                else
                    ax.Box = 'off';
                    ax.LineWidth = 0.5;
                end
            end
        end

        % ---- 通道表回调 ----

        function OnChannelEdit(obj, e)
        % OnChannelEdit 单元格编辑：列1=复选框，列2=通道名（仅子行）
            if obj.Rebuilding_, return; end
            visRow = e.Indices(1);
            col = e.Indices(2);
            if visRow < 1 || visRow > numel(obj.VisibleRowMap_)
                return;
            end
            internalIdx = obj.VisibleRowMap_(visRow);
            r = obj.ChannelRows_(internalIdx);

            if col == 2
                % 列2编辑仅在重命名模式下有效
                if ~obj.Renaming_
                    return;
                end
                obj.Renaming_ = false;
                obj.ChannelTable.ColumnEditable(2) = false;
                newName = strtrim(obj.ChannelTable.Data{visRow, 2});
                % 名称无变化或为空 → 视为取消，恢复原名
                if isempty(newName) || strcmp(newName, obj.RenameOriginal_)
                    obj.Rebuilding_ = true;
                    obj.ChannelTable.Data{visRow, 2} = r.label;
                    obj.Rebuilding_ = false;
                    return;
                end
                if r.isParent
                    notify(obj, 'InlineRenameDataset', AppEventData(struct(...
                        'datasetIdx', r.datasetIdx, 'newName', newName)));
                else
                    notify(obj, 'InlineRenameChannel', AppEventData(struct(...
                        'datasetIdx', r.datasetIdx, 'colIdx', r.colIdx, 'newName', newName)));
                end
                return;
            end

            % 列1：复选框勾选（View 只广播事件，Presenter 处理级联逻辑）
            val = logical(obj.ChannelTable.Data{visRow, 1});
            if r.isParent
                notify(obj, 'ChannelCheckChanged', ...
                    AppEventData(struct('datasetIdx', r.datasetIdx, 'colIdx', 0, 'checked', val)));
            else
                notify(obj, 'ChannelCheckChanged', ...
                    AppEventData(struct('datasetIdx', r.datasetIdx, 'colIdx', r.colIdx, 'checked', val)));
            end
        end

        function OnChannelSelect(obj, e)
        % OnChannelSelect 点击行展开/折叠（只负责数据集展开，不改变勾选状态）
            if obj.Highlighting_ || obj.Rebuilding_
                return;
            end
            % 重命名期间点击其他行 → 取消重命名
            if obj.Renaming_
                obj.Renaming_ = false;
                obj.ChannelTable.ColumnEditable(2) = false;
                return;
            end
            if isempty(e.Indices)
                return;
            end
            visRow = e.Indices(1);
            obj.LastClickedRow_ = visRow;
            if visRow < 1 || visRow > numel(obj.VisibleRowMap_)
                return;
            end
            internalIdx = obj.VisibleRowMap_(visRow);
            r = obj.ChannelRows_(internalIdx);
            if ~r.isParent
                return;
            end
            dsIdx = r.datasetIdx;
            if obj.ExpandedSets_.isKey(dsIdx)
                obj.ExpandedSets_(dsIdx) = ~obj.ExpandedSets_(dsIdx);
            else
                obj.ExpandedSets_(dsIdx) = true;
            end
            obj.SetChannelTable(obj.ChannelRows_);
            % 重建后重选该行：保持高亮供右键使用，且下次点击同一行选择变化可再次触发回调
            obj.Highlighting_ = true;
            obj.ChannelTable.Selection = [visRow, 1; visRow, 2];
            obj.Highlighting_ = false;
        end

        function OnContextMenuOpening(obj)
        % OnContextMenuOpening 右键时自动选中最近左键点击的行，并更新菜单可用性
            if obj.LastClickedRow_ >= 1 && obj.LastClickedRow_ <= size(obj.ChannelTable.Data, 1)
                obj.Highlighting_ = true;
                obj.ChannelTable.Selection = [obj.LastClickedRow_, 1; obj.LastClickedRow_, 2];
                obj.Highlighting_ = false;
            end

            % 判断选中行类型，更新横轴/右Y轴菜单可用性
            isChannel = false;
            dsIdx = 0; chIdx = 0;
            if ~isempty(obj.VisibleRowMap_) && obj.LastClickedRow_ >= 1 ...
                    && obj.LastClickedRow_ <= numel(obj.VisibleRowMap_)
                ci = obj.VisibleRowMap_(obj.LastClickedRow_);
                r = obj.ChannelRows_(ci);
                isChannel = ~r.isParent;
                if isChannel
                    dsIdx = r.datasetIdx;
                    chIdx = r.colIdx;
                end
            end

            isXChannel = isChannel && ~isempty(obj.CurXChannel_) ...
                && obj.CurXChannel_(1) == dsIdx && obj.CurXChannel_(2) == chIdx;
            % 检查是否在右Y列表中
            isRightY = false;
            if isChannel && ~isempty(obj.CurRightYChannel_)
                for ri = 1:length(obj.CurRightYChannel_)
                    if obj.CurRightYChannel_{ri}(1) == dsIdx && obj.CurRightYChannel_{ri}(2) == chIdx
                        isRightY = true;
                        break;
                    end
                end
            end

            obj.SetMenuEnable(obj.MenuSetXAxis_, isChannel && ~isXChannel);
            obj.SetMenuEnable(obj.MenuClearXAxis_, isChannel && isXChannel);
            obj.SetMenuEnable(obj.MenuSetRightY_, isChannel && ~isRightY && ~isXChannel);
            obj.SetMenuEnable(obj.MenuClearRightY_, isChannel && isRightY);
            % 父行禁用：采样频率、切片范围、切片重置
            cm = obj.ChannelTable.ContextMenu;
            for mi = 1:numel(cm.Children)
                item = cm.Children(mi);
                if strcmp(item.Text, '设置采样频率...') || ...
                   strcmp(item.Text, '设置切片范围...') || ...
                   strcmp(item.Text, '切片重置')
                    obj.SetMenuEnable(item, isChannel);
                end
            end
        end

        function OnContextRename(obj)
        % OnContextRename 右键重命名：临时开启列编辑，禁用展开/折叠
            sel = obj.ChannelTable.Selection;
            if isempty(sel) || isempty(obj.VisibleRowMap_)
                return;
            end
            visRow = sel(1, 1);
            if visRow < 1 || visRow > numel(obj.VisibleRowMap_)
                return;
            end
            internalIdx = obj.VisibleRowMap_(visRow);
            r = obj.ChannelRows_(internalIdx);
            obj.RenameOriginal_ = r.label;
            obj.Renaming_ = true;
            obj.ChannelTable.ColumnEditable(2) = true;
            obj.ChannelTable.Selection = [visRow, 2];
            % 需要两次设置才能进入编辑模式：先选中再更新
            drawnow;
            obj.ChannelTable.Selection = [visRow, 2];
        end

        function OnContextAction(obj, action)
            sel = obj.ChannelTable.Selection;
            if isempty(sel) || isempty(obj.VisibleRowMap_)
                return;
            end
            rows = unique(sel(:, 1));  % 提取行号（兼容 cell/row 选择模式）
            switch action
                case 'exportExcel'
                    for s = 1:numel(rows)
                        visRow = rows(s);
                        if visRow < 1 || visRow > numel(obj.VisibleRowMap_), continue; end
                        ci = obj.VisibleRowMap_(visRow);
                        r = obj.ChannelRows_(ci);
                        if ~r.isParent, continue; end
                        notify(obj, 'ExportExcelClicked', AppEventData(struct('datasetIdx', r.datasetIdx)));
                    end
            end
        end

        function OnContextChannelAction(obj, action)
            visRow = obj.GetContextRow();
            if isempty(visRow)
                return;
            end
            internalIdx = obj.VisibleRowMap_(visRow);
            r = obj.ChannelRows_(internalIdx);
            if r.isParent
                return;
            end
            payload = AppEventData(struct('datasetIdx', r.datasetIdx, 'colIdx', r.colIdx));
            switch action
                case 'slice'
                    notify(obj, 'SliceDialogClicked', payload);
                case 'sliceReset'
                    notify(obj, 'SliceResetClicked', payload);
                case 'setSampleRate'
                    notify(obj, 'SetSampleRateClicked', payload);
                case 'setXAxis'
                    notify(obj, 'SetXAxisClicked', payload);
                case 'clearXAxis'
                    notify(obj, 'ClearXAxisClicked', AppEventData(struct('axesIdx', obj.GetFocusedAxes())));
                case 'setRightY'
                    notify(obj, 'SetRightYAxisClicked', payload);
                case 'clearRightY'
                    notify(obj, 'ClearRightYAxisClicked', AppEventData(struct('axesIdx', obj.GetFocusedAxes())));
            end
        end

        function row = GetContextRow(obj)
        % GetContextRow 右键命中的可见表格行号
            row = [];
            sel = obj.ChannelTable.Selection;
            if isempty(sel) || isempty(obj.VisibleRowMap_)
                return;
            end
            row = sel(1);
            if row < 1 || row > numel(obj.VisibleRowMap_)
                row = [];
            end
        end

        function OnNormClicked(obj)
            items = obj.NormDropdown.Items;
            modes = {'none', 'minmax', 'zscore', 'meanzero'};
            idx = find(strcmp(obj.NormDropdown.Value, items), 1);
            if isempty(idx) || idx > numel(modes)
                return;
            end
            notify(obj, 'NormClicked', AppEventData(struct('mode', modes{idx})));
        end

        function CleanupBrokenLegends(obj)
        % CleanupBrokenLegends 删除空条目 legend（隐藏页签内创建产生的工件）
            fig = ancestor(obj.Grid_, 'figure');
            legs = findobj(fig, 'Type', 'legend');
            for i = 1:numel(legs)
                if isempty(legs(i).PlotChildren)
                    delete(legs(i));
                end
            end
        end

        function SetMenuEnable(~, menuItem, enabled)
        % SetMenuEnable 设置菜单项可用性
            if isvalid(menuItem)
                if enabled
                    menuItem.Enable = 'on';
                else
                    menuItem.Enable = 'off';
                end
            end
        end

        function RefreshLegendFor(obj, ax)
        % RefreshLegendFor 为指定 uiaxes 重建 legend（若无 legend 且 ≥2 条线）
            fig = ancestor(obj.Grid_, 'figure');
            legs = findobj(fig, 'Type', 'legend');
            hasLegend = false;
            for i = 1:numel(legs)
                kids = legs(i).PlotChildren;
                if ~isempty(kids) && any(arrayfun(@(k) isequal(ancestor(k, 'axes'), ax), kids))
                    hasLegend = true;
                end
            end
            if hasLegend
                return;
            end
            lines = findobj(ax, 'Type', 'line');
            if numel(lines) >= 2
                legend(ax, 'Interpreter', 'none', 'Location', 'northwest');
            end
        end
    end

    methods
        % ---- 弹窗工厂（Presenter 调用，View 负责 UI 创建） ----

        function h = CreateSpectrumPopup(obj)
        % CreateSpectrumPopup 创建频谱分析弹窗骨架
        %
        % 输出 h：struct，含 fig / axTime / axFreq / modeDropdown
        % Presenter 负责注册生命周期和填充数据

            fig = uifigure('Name', 'Spectrum Analysis', ...
                'NumberTitle', 'off', 'Position', [200 150 900 720]);

            g = uigridlayout(fig, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [6 6 6 6], 'RowSpacing', 4);

            axTime = uiaxes(g);
            axTime.Layout.Row = 1;
            axFreq = uiaxes(g);
            axFreq.Layout.Row = 2;

            h = struct('fig', fig, 'axTime', axTime, 'axFreq', axFreq);
        end

        function h = CreateCalcDialog(obj, channelList)
        % CreateCalcDialog 创建通道运算对话框骨架
        %
        % 输入：
        %   channelList - cell 通道名称列表
        %
        % 输出 h：struct，含全部 UI 句柄，Presenter 负责回调和数据填充

            opTypes = {'A + B', 'A - B', 'A × B', 'A ÷ B', ...
                       'diff(A)', 'cumsum(A)', '|A|', 'A²', '√A', ...
                       'log₁₀(A)', 'detrend(A)', 'RMS(A)', 'smooth(A)'};

            fig = uifigure('Name', '通道运算', ...
                'NumberTitle', 'off', 'Position', [400 260 380 440], ...
                'Resize', 'off');

            g = uigridlayout(fig, [10 2], ...
                'RowHeight', [repmat({28}, 1, 9), {36}], ...
                'ColumnWidth', {110, '1x'}, ...
                'Padding', [10 10 10 10], 'RowSpacing', 5);

            uilabel(g, 'Text', '运算类型:');
            opPopup = uidropdown(g, 'Items', opTypes, 'Value', opTypes{1});
            uilabel(g, 'Text', '通道A:');
            popupA = uidropdown(g, 'Items', channelList, 'Value', channelList{1});
            uilabel(g, 'Text', '通道B:');
            popupB = uidropdown(g, 'Items', channelList, 'Value', channelList{1}, ...
                'Enable', 'off');
            uilabel(g, 'Text', 'A 起点:');
            editA1 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf]);
            uilabel(g, 'Text', 'A 长度:');
            editA2 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf]);
            uilabel(g, 'Text', 'B 起点:');
            editB1 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf], 'Enable', 'off');
            uilabel(g, 'Text', 'B 长度:');
            editB2 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf], 'Enable', 'off');
            winLabel = uilabel(g, 'Text', '窗口大小:');
            winLabel.Visible = 'off';
            editWin = uieditfield(g, 'numeric', 'Value', 10, 'Limits', [2 inf]);
            editWin.Visible = 'off';
            uilabel(g, 'Text', '结果名称:');
            editName = uieditfield(g, 'text', 'Value', '');
            btnGrid = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', '1x'}, ...
                'ColumnSpacing', 8, 'RowHeight', {28}, 'Padding', [0 0 0 0]);
            btnGrid.Layout.Column = [1 2];
            btnOk = uibutton(btnGrid, 'push', 'Text', '确定');
            btnCancel = uibutton(btnGrid, 'push', 'Text', '取消');

            h = struct('fig', fig, ...
                       'opPopup', opPopup, 'popupA', popupA, 'popupB', popupB, ...
                       'editA1', editA1, 'editA2', editA2, ...
                       'editB1', editB1, 'editB2', editB2, ...
                       'winLabel', winLabel, 'editWin', editWin, ...
                       'editName', editName, ...
                       'btnOk', btnOk, 'btnCancel', btnCancel);
        end

        function result = ShowSampleRateDialog(~, dsName, defaultVal)
        % ShowSampleRateDialog 弹窗输入采样率
        %
        % 输入：
        %   dsName     - 数据集名称
        %   defaultVal - 默认值（数字或字符串）
        %
        % 输出：
        %   result - 用户输入的采样率数值，取消返回 []

            if nargin < 3, defaultVal = ''; end
            result = [];
            dlg = dialog('Name', '设置采样率', 'Position', [400 350 340 160], ...
                'WindowStyle', 'modal', 'Resize', 'off');
            uicontrol('Parent', dlg, 'Style', 'text', ...
                'String', sprintf('数据集: %s', dsName), ...
                'FontSize', 10, ...
                'Position', [14 120 312 22], 'HorizontalAlignment', 'left');
            uicontrol('Parent', dlg, 'Style', 'text', ...
                'String', '采样率 (Hz):', ...
                'FontSize', 10, ...
                'Position', [14 86 100 22], 'HorizontalAlignment', 'left');
            editRate = uicontrol('Parent', dlg, 'Style', 'edit', ...
                'String', defaultVal, 'FontSize', 10, ...
                'Position', [120 84 196 26]);
            uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
                'String', '确定', 'FontSize', 10, ...
                'Position', [150 14 70 30], ...
                'Callback', @(~, ~) doOk());
            uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
                'String', '取消', 'FontSize', 10, ...
                'Position', [240 14 70 30], ...
                'Callback', @(~, ~) delete(dlg));
            uiwait(dlg);
            function doOk()
                v = str2double(get(editRate, 'String'));
                if ~isnan(v) && v > 0
                    result = v;
                    uiresume(dlg); delete(dlg);
                else
                    errordlg('采样率必须为正数', '输入错误', 'modal');
                end
            end
        end

        function result = ShowSliceRangeDialog(~, colName, totalRows, defaultStart, defaultLen)
        % ShowSliceRangeDialog 弹窗输入切片范围
        %
        % 输出：
        %   result - [start, len] 或 []

            result = [];
            dlg = dialog('Name', sprintf('切片范围 - %s', colName), ...
                'Position', [400 350 340 200], ...
                'WindowStyle', 'modal', 'Resize', 'off');
            uicontrol('Parent', dlg, 'Style', 'text', ...
                'String', sprintf('共 %d 行', totalRows), ...
                'FontSize', 10, ...
                'Position', [14 162 312 22], 'HorizontalAlignment', 'left');
            uicontrol('Parent', dlg, 'Style', 'text', ...
                'String', '起点行号:', ...
                'FontSize', 10, ...
                'Position', [14 128 100 22], 'HorizontalAlignment', 'left');
            editStart = uicontrol('Parent', dlg, 'Style', 'edit', ...
                'String', num2str(defaultStart), 'FontSize', 10, ...
                'Position', [120 126 196 26]);
            uicontrol('Parent', dlg, 'Style', 'text', ...
                'String', '长度:', ...
                'FontSize', 10, ...
                'Position', [14 92 100 22], 'HorizontalAlignment', 'left');
            editLen = uicontrol('Parent', dlg, 'Style', 'edit', ...
                'String', num2str(defaultLen), 'FontSize', 10, ...
                'Position', [120 90 196 26]);
            uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
                'String', '确定', 'FontSize', 10, ...
                'Position', [150 14 70 30], ...
                'Callback', @(~, ~) doOk());
            uicontrol('Parent', dlg, 'Style', 'pushbutton', ...
                'String', '取消', 'FontSize', 10, ...
                'Position', [240 14 70 30], ...
                'Callback', @(~, ~) delete(dlg));
            uiwait(dlg);
            function doOk()
                s = round(str2double(get(editStart, 'String')));
                l = round(str2double(get(editLen, 'String')));
                if ~isnan(s) && ~isnan(l) && s >= 1 && l >= 1
                    result = [s, l];
                    uiresume(dlg); delete(dlg);
                else
                    errordlg('起点 ≥1, 长度 ≥1', '输入错误', 'modal');
                end
            end
        end

        function h = CreateExportFigure(obj, name)
        % CreateExportFigure 创建导出用 figure（非 uifigure）
        %
        % 输出 h：figure 句柄，Presenter 负责 subplot/plot 内容

            h = figure('Name', name, 'NumberTitle', 'off');
        end

        % ---- 游标鼠标回调 ----

        function onCursorMotionWrapper(obj, oldFcn)
        % onCursorMotionWrapper 保留旧回调 + 游标移动
            if ~isempty(oldFcn)
                try oldFcn(); catch, end
            end
            obj.onCursorMotion();
        end

        function onCursorMotion(obj)
        % onCursorMotion 全局鼠标移动：边界保护 + 节流 + 事件广播
            persistent lastT;
            if ~isempty(lastT) && toc(lastT) < 0.05, return; end
            lastT = tic;

            for i = 1:obj.AxesCount_
                ax = obj.AxesHandles_{i};
                cp = ax.CurrentPoint;
                xl = xlim(ax); yl = ylim(ax);
                if cp(1,1) >= xl(1) && cp(1,1) <= xl(2) && ...
                   cp(1,2) >= yl(1) && cp(1,2) <= yl(2)
                    notify(obj, 'CursorMotion', ...
                        AppEventData(struct('axesIdx', i, 'x', cp(1,1))));
                    return;
                end
            end
            obj.HideCursor();
        end
    end
end
