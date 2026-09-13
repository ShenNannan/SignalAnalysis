classdef TransferFunctionView < handle
% TransferFunctionView - 传函分析视图（FRF 频响查看器，哑终端）
%
% 只做控件装配、渲染与事件广播，零业务逻辑。
% 布局：顶行（路径 + Browse/Import）| 左（曲线勾选表）右（幅值/相位/相关性 3 子图）

    properties (SetAccess = private)
        Grid_           % 顶层 uigridlayout
        PathEdit        % uieditfield
        CurveTable      % uitable（logical 勾选列 + 曲线名列）
        AmpAxes         % uiaxes 幅值
        PhaseAxes       % uiaxes 相位
        CorrAxes        % uiaxes 相关性
        LoadingDlg_     % uiprogressdlg
    end

    events
        BrowseClicked           % 浏览按钮
        ImportButtonClicked     % 导入按钮（路径经 GetPath 读取）
        CurveSelectionChanged   % 载荷 struct('row', 行号)
    end

    methods
        function obj = TransferFunctionView(parent)
            obj.Grid_ = uigridlayout(parent, [2 1], ...
                'RowHeight', {36, '1x'}, ...
                'Padding', [8 8 8 8], ...
                'RowSpacing', 6);
            obj.LoadingDlg_ = [];

            obj.BuildTopBar();
            obj.BuildMainArea();
        end

        function path = GetPath(obj)
            path = obj.PathEdit.Value;
        end

        function SetPath(obj, path)
            obj.PathEdit.Value = path;
        end

        function SetCurveList(obj, names, checked)
        % SetCurveList 填充曲线勾选表
            n = numel(names);
            if nargin < 3 || isempty(checked)
                checked = true(n, 1);
            end
            obj.CurveTable.Data = table(checked(:), names(:), ...
                'VariableNames', {'选择', '曲线'});
        end

        function checked = GetCurveSelection(obj)
            data = obj.CurveTable.Data;
            if isempty(data)
                checked = [];
                return;
            end
            checked = data.(1);
        end

        function ClearPlots(obj)
            cla(obj.AmpAxes);
            cla(obj.PhaseAxes);
            cla(obj.CorrAxes);
        end

        function RenderFrf(obj, curves)
        % RenderFrf 在三张子图上叠画 FRF 曲线（跳过 Freq=0，Corr ylim [0 1]）
            obj.ClearPlots();
            nPlotted = 0;
            for i = 1:numel(curves)
                c = curves(i);
                mask = c.freq > 0;
                if ~any(mask)
                    continue;
                end
                nPlotted = nPlotted + 1;
                semilogx(obj.AmpAxes, c.freq(mask), c.amp(mask), 'DisplayName', c.name);
                hold(obj.AmpAxes, 'on');
                semilogx(obj.PhaseAxes, c.freq(mask), c.phase(mask), 'DisplayName', c.name);
                hold(obj.PhaseAxes, 'on');
                semilogx(obj.CorrAxes, c.freq(mask), c.corr(mask), 'DisplayName', c.name);
                hold(obj.CorrAxes, 'on');
            end
            hold(obj.AmpAxes, 'off');
            hold(obj.PhaseAxes, 'off');
            hold(obj.CorrAxes, 'off');
            ylim(obj.CorrAxes, [0 1]);

            % legend 在隐藏页签内创建会得到空条目（MATLAB 渲染初始化限制），
            % 统一走 RefreshLegends：切换页签可见后由 app 再次触发
            obj.RefreshLegends();
        end

        function RefreshLegends(obj)
        % RefreshLegends 为三张子图重建 legend（页签切换可见后由 app 调用）
            obj.CleanupBrokenLegends();
            obj.RefreshLegendFor(obj.AmpAxes);
            obj.RefreshLegendFor(obj.PhaseAxes);
            obj.RefreshLegendFor(obj.CorrAxes);
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
        function BuildTopBar(obj)
            top = uigridlayout(obj.Grid_, [1 4], ...
                'ColumnWidth', {70, '1x', 90, 70}, ...
                'ColumnSpacing', 6);
            top.Layout.Row = 1;

            uilabel(top, 'Text', '数据路径:', 'HorizontalAlignment', 'right');
            obj.PathEdit = uieditfield(top, 'text', 'Value', '');
            uibutton(top, 'push', 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'BrowseClicked'));
            uibutton(top, 'push', 'Text', 'Import', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ImportButtonClicked'));
        end

        function BuildMainArea(obj)
            main = uigridlayout(obj.Grid_, [1 2], ...
                'ColumnWidth', {240, '1x'}, ...
                'ColumnSpacing', 6);
            main.Layout.Row = 2;

            obj.CurveTable = uitable(main, ...
                'ColumnName', {'选择', '曲线'}, ...
                'ColumnEditable', [true false], ...
                'ColumnWidth', {36, '1x'});
            obj.CurveTable.Layout.Column = 1;
            obj.CurveTable.Data = table(true(0, 1), cell(0, 1), ...
                'VariableNames', {'选择', '曲线'});
            obj.CurveTable.CellEditCallback = @(s, e) obj.OnCurveEdit(e);

            plots = uigridlayout(main, [3 1], ...
                'RowHeight', {'1x', '1x', '1x'}, ...
                'RowSpacing', 4);
            plots.Layout.Column = 2;

            obj.AmpAxes = uiaxes(plots);
            obj.AmpAxes.Layout.Row = 1;
            title(obj.AmpAxes, '幅值 Amp vs Freq');
            ylabel(obj.AmpAxes, 'Magnitude (dB)');
            grid(obj.AmpAxes, 'on');

            obj.PhaseAxes = uiaxes(plots);
            obj.PhaseAxes.Layout.Row = 2;
            title(obj.PhaseAxes, '相位 Phase vs Freq');
            ylabel(obj.PhaseAxes, 'Phase (deg)');
            grid(obj.PhaseAxes, 'on');

            obj.CorrAxes = uiaxes(plots);
            obj.CorrAxes.Layout.Row = 3;
            title(obj.CorrAxes, '相关性 Corr vs Freq');
            xlabel(obj.CorrAxes, 'Frequency (Hz)');
            ylabel(obj.CorrAxes, 'Coherence');
            grid(obj.CorrAxes, 'on');
        end

        function OnCurveEdit(obj, e)
            notify(obj, 'CurveSelectionChanged', struct('row', e.Indices(1)));
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
