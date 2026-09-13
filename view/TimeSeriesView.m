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
        NormDropdown    % uidropdown 归一化模式
        LoadingDlg_     % uiprogressdlg
    end

    properties (Access = private)
        ChannelRows_    % struct array：datasetIdx/colIdx/label/datasetName/checked
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
        ClearPlotClicked
        FftClicked
        PsdClicked
        NormClicked             % 载荷 struct('mode',..)
        CalcClicked
        AxesClicked             % 载荷 struct('axesIdx',..,'x',..,'y',..)
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
            obj.LoadingDlg_ = [];

            obj.BuildChannelPanel();
            obj.BuildPlotPanel();
            obj.AddAxesInternal();
        end

        % ---- 通道表 ----

        function SetChannelTable(obj, rows)
        % SetChannelTable 填充通道表（rows: datasetIdx/colIdx/label/datasetName/checked）
            obj.ChannelRows_ = rows;
            n = numel(rows);
            checked = false(n, 1);
            chNames = cell(n, 1);
            dsNames = cell(n, 1);
            for i = 1:n
                checked(i) = rows(i).checked;
                chNames{i} = rows(i).label;
                dsNames{i} = rows(i).datasetName;
            end
            obj.ChannelTable.Data = table(checked, chNames, dsNames, ...
                'VariableNames', {'选择', '通道', '数据集'});
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
                cla(ax);
            end
        end

        function ClearAllAxes(obj)
            for i = 1:obj.AxesCount_
                obj.ClearAxes(i);
            end
        end

        % ---- 渲染接口 ----

        function RenderWaveform(obj, axesIdx, xCell, yCell, labels, colors)
        % RenderWaveform 在指定 axes 叠画多条通道
            ax = obj.GetAxes(axesIdx);
            if isempty(ax) || ~isvalid(ax)
                return;
            end
            cla(ax);
            hold(ax, 'on');
            for c = 1:numel(yCell)
                plot(ax, xCell{c}, yCell{c}, 'Color', colors{c}, 'DisplayName', labels{c});
            end
            hold(ax, 'off');
            grid(ax, 'on');
            ylabel(ax, 'Amplitude');

            % legend 在隐藏页签内创建会得到空条目，统一走 RefreshLegendFor
            obj.RefreshLegendFor(ax);
        end

        function RefreshLegends(obj)
        % RefreshLegends 为全部 axes 重建 legend（页签切换可见后由 app 调用）
            obj.CleanupBrokenLegends();
            for i = 1:obj.AxesCount_
                obj.RefreshLegendFor(obj.AxesHandles_{i});
            end
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
    end

    methods (Access = private)
        function BuildChannelPanel(obj)
            left = uigridlayout(obj.Grid_, [2 1], ...
                'RowHeight', {'1x', 30}, ...
                'RowSpacing', 4);
            left.Layout.Column = 1;

            obj.ChannelTable = uitable(left, ...
                'ColumnName', {'选择', '通道', '数据集'}, ...
                'ColumnEditable', [true false false], ...
                'ColumnWidth', {36, '1x', '1x'}, ...
                'SelectionType', 'row');
            obj.ChannelTable.Layout.Row = 1;
            obj.ChannelTable.Data = table(false(0, 1), cell(0, 1), cell(0, 1), ...
                'VariableNames', {'选择', '通道', '数据集'});
            obj.ChannelTable.CellEditCallback = @(s, e) obj.OnChannelEdit(e);

            cm = uicontextmenu(ancestor(left, 'figure'));
            uimenu(cm, 'Text', '勾选本数据集全部', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextAction('checkAll'));
            uimenu(cm, 'Text', '取消本数据集全部', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextAction('uncheckAll'));
            uimenu(cm, 'Text', '导出 Excel(本数据集)', ...
                'MenuSelectedFcn', @(s, e) obj.OnContextAction('exportExcel'));
            obj.ChannelTable.ContextMenu = cm;

            btns = uigridlayout(left, [1 3], ...
                'ColumnWidth', {'1x', '1x', '1x'}, ...
                'ColumnSpacing', 4);
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
            tb = uigridlayout(parent, [1 11], ...
                'ColumnWidth', {34, 34, 34, 34, 60, 70, 50, 50, 100, 50, 50}, ...
                'ColumnSpacing', 3);
            tb.Layout.Row = 1;

            uibutton(tb, 'push', 'Text', '+', 'FontWeight', 'bold', ...
                'ButtonPushedFcn', @(s, e) obj.OnAddAxesClicked());
            uibutton(tb, 'push', 'Text', '×', ...
                'ButtonPushedFcn', @(s, e) obj.OnRemoveAxesClicked());
            uibutton(tb, 'push', 'Text', '||', ...
                'ButtonPushedFcn', @(s, e) obj.OnLayoutClicked('single'));
            uibutton(tb, 'push', 'Text', '=', ...
                'ButtonPushedFcn', @(s, e) obj.OnLayoutClicked('dual'));
            uibutton(tb, 'push', 'Text', 'Export', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ExportClicked'));
            uibutton(tb, 'push', 'Text', 'Clear Plot', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ClearPlotClicked'));
            uibutton(tb, 'push', 'Text', 'FFT', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'FftClicked'));
            uibutton(tb, 'push', 'Text', 'PSD', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'PsdClicked'));
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
            notify(obj, 'LayoutChanged', struct('mode', mode));
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
            valid = {};
            for i = 1:numel(obj.AxesHandles_)
                a = obj.AxesHandles_{i};
                if ~isempty(a) && isvalid(a)
                    valid{end+1} = a; %#ok<AGROW>
                end
            end
            if numel(valid) >= 2
                linkaxes([valid{:}], 'x');
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
            notify(obj, 'AxesClicked', struct('axesIdx', axesIdx, 'x', x, 'y', y));
        end

        function UpdateAxesHighlight(obj)
            for i = 1:obj.AxesCount_
                ax = obj.AxesHandles_{i};
                if i == obj.FocusedAxes_
                    ax.Box = 'on';
                    ax.XColor = [0.8 0.2 0.2];
                    ax.YColor = [0.8 0.2 0.2];
                else
                    ax.Box = 'off';
                    ax.XColor = [0.15 0.15 0.15];
                    ax.YColor = [0.15 0.15 0.15];
                end
            end
        end

        % ---- 通道表回调 ----

        function OnChannelEdit(obj, e)
            row = e.Indices(1);
            if isempty(obj.ChannelRows_) || row > numel(obj.ChannelRows_)
                return;
            end
            r = obj.ChannelRows_(row);
            val = obj.ChannelTable.Data{row, 1};
            notify(obj, 'ChannelCheckChanged', ...
                struct('datasetIdx', r.datasetIdx, 'colIdx', r.colIdx, 'checked', val));
        end

        function OnContextAction(obj, action)
            % 右键会先选中该行（SelectionType='row'），从 Selection 取行号
            sel = obj.ChannelTable.Selection;
            if isempty(sel)
                return;
            end
            row = sel(1);
            if isempty(obj.ChannelRows_) || row > numel(obj.ChannelRows_)
                return;
            end
            d = obj.ChannelRows_(row).datasetIdx;
            switch action
                case 'exportExcel'
                    notify(obj, 'ExportExcelClicked', struct('datasetIdx', d));
                case {'checkAll', 'uncheckAll'}
                    newVal = strcmp(action, 'checkAll');
                    for i = 1:numel(obj.ChannelRows_)
                        if obj.ChannelRows_(i).datasetIdx == d
                            obj.ChannelTable.Data{i, 1} = newVal;
                        end
                    end
                    notify(obj, 'ChannelCheckChanged', ...
                        struct('datasetIdx', d, 'colIdx', 0, 'checked', newVal));
            end
        end

        function OnNormClicked(obj)
            items = obj.NormDropdown.Items;
            modes = {'none', 'minmax', 'zscore', 'meanzero'};
            idx = find(strcmp(obj.NormDropdown.Value, items), 1);
            if isempty(idx) || idx > numel(modes)
                return;
            end
            notify(obj, 'NormClicked', struct('mode', modes{idx}));
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
                legend(ax);
            end
        end
    end
end
