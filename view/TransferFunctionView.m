classdef TransferFunctionView < handle
% TransferFunctionView - 传函分析视图（FRF 频响查看器，哑终端）
%
% 只做控件装配、渲染与事件广播，零业务逻辑。
% 布局：左（路径 + 曲线勾选表 + Browse/Import）| 右（幅值/相位/相关性 3 子图）
% 与 TimeSeriesView 保持一致的左右分栏布局。

    properties (SetAccess = private)
        Grid_           % 顶层 uigridlayout
        CurveTable      % uitable（logical 勾选列 + 曲线名列）
        AmpAxes         % uiaxes 幅值
        PhaseAxes       % uiaxes 相位
        CorrAxes        % uiaxes 相关性
        LoadingDlg_     % uiprogressdlg
    end

    properties (Access = private)
        Path_           % 当前选择的路径
    end

    events
        BrowseClicked           % 浏览按钮
        ImportButtonClicked     % 导入按钮（路径经 GetPath 读取）
        ClearAllClicked         % 清空全部
        CurveSelectionChanged   % 载荷 struct('row', 行号)
    end

    methods
        function obj = TransferFunctionView(parent)
            obj.Grid_ = uigridlayout(parent, [1 2], ...
                'ColumnWidth', {'22x', '78x'}, ...
                'Padding', [6 6 6 6], ...
                'ColumnSpacing', 6);
            obj.LoadingDlg_ = [];

            obj.BuildLeftPanel();
            obj.BuildRightPanel();
        end

        function path = GetPath(obj)
            path = obj.Path_;
        end

        function SetPath(obj, path)
            obj.Path_ = path;
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
            cla(obj.AmpAxes, 'reset');
            cla(obj.PhaseAxes, 'reset');
            cla(obj.CorrAxes, 'reset');
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
        % ShowLoading 显示阻断式加载弹窗
            if nargin < 2, msg = '处理中...'; end
            obj.LoadingDlg_ = uiprogressdlg(ancestor(obj.Grid_, 'figure'), ...
                'Title', '请稍候', 'Message', msg, 'Indeterminate', 'on');
            drawnow;
        end

        function CloseLoading(obj)
        % CloseLoading 关闭加载弹窗
            if ~isempty(obj.LoadingDlg_) && isvalid(obj.LoadingDlg_)
                close(obj.LoadingDlg_);
            end
            obj.LoadingDlg_ = [];
        end

        function ShowError(obj, msg)
            ViewUtils.ShowError(obj, msg);
        end
    end

    methods (Access = private)
        function BuildLeftPanel(obj)
            left = uigridlayout(obj.Grid_, [2 1], ...
                'RowHeight', {'1x', 36}, ...
                'RowSpacing', 6, ...
                'Padding', [0 0 0 0]);
            left.Layout.Column = 1;

            % 曲线勾选表
            obj.CurveTable = uitable(left, ...
                'ColumnName', {'选择', '曲线'}, ...
                'ColumnEditable', [true false], ...
                'ColumnWidth', {38, '1x'});
            obj.CurveTable.Layout.Row = 1;
            obj.CurveTable.Data = table(true(0, 1), cell(0, 1), ...
                'VariableNames', {'选择', '曲线'});
            obj.CurveTable.CellEditCallback = @(s, e) obj.OnCurveEdit(e);

            % Browse / Import / Clear All 按钮
            btns = uigridlayout(left, [1 3], ...
                'ColumnWidth', {'1x', '1x', '1x'}, ...
                'ColumnSpacing', 4, ...
                'Padding', [0 0 0 0]);
            btns.Layout.Row = 2;
            uibutton(btns, 'push', 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'BrowseClicked'));
            uibutton(btns, 'push', 'Text', 'Import', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ImportButtonClicked'));
            uibutton(btns, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(s, e) notify(obj, 'ClearAllClicked'));
        end

        function BuildRightPanel(obj)
            plots = uigridlayout(obj.Grid_, [3 1], ...
                'RowHeight', {'1x', '1x', '1x'}, ...
                'RowSpacing', 4, ...
                'Padding', [0 0 0 0]);
            plots.Layout.Column = 2;

            obj.AmpAxes = uiaxes(plots);
            yyaxis(obj.AmpAxes, 'right'); cla(obj.AmpAxes); obj.AmpAxes.YAxis(2).Visible = 'off';
            yyaxis(obj.AmpAxes, 'left'); cla(obj.AmpAxes);
            obj.AmpAxes.Layout.Row = 1;
            title(obj.AmpAxes, '幅值 Amp vs Freq');
            ylabel(obj.AmpAxes, 'Magnitude (dB)');
            grid(obj.AmpAxes, 'on');

            obj.PhaseAxes = uiaxes(plots);
            yyaxis(obj.PhaseAxes, 'right'); cla(obj.PhaseAxes); obj.PhaseAxes.YAxis(2).Visible = 'off';
            yyaxis(obj.PhaseAxes, 'left'); cla(obj.PhaseAxes);
            obj.PhaseAxes.Layout.Row = 2;
            title(obj.PhaseAxes, '相位 Phase vs Freq');
            ylabel(obj.PhaseAxes, 'Phase (deg)');
            grid(obj.PhaseAxes, 'on');

            obj.CorrAxes = uiaxes(plots);
            yyaxis(obj.CorrAxes, 'right'); cla(obj.CorrAxes); obj.CorrAxes.YAxis(2).Visible = 'off';
            yyaxis(obj.CorrAxes, 'left'); cla(obj.CorrAxes);
            obj.CorrAxes.Layout.Row = 3;
            title(obj.CorrAxes, '相关性 Corr vs Freq');
            xlabel(obj.CorrAxes, 'Frequency (Hz)');
            ylabel(obj.CorrAxes, 'Coherence');
            grid(obj.CorrAxes, 'on');
        end

        function OnCurveEdit(obj, e)
            notify(obj, 'CurveSelectionChanged', AppEventData(struct('row', e.Indices(1))));
        end

        function CleanupBrokenLegends(obj)
        % CleanupBrokenLegends 删除空条目 legend（隐藏页签内创建产生的工件）
            ViewUtils.CleanupBrokenLegends(ancestor(obj.Grid_, 'figure'));
        end

        function RefreshLegendFor(obj, ax)
        % RefreshLegendFor 为指定 uiaxes 重建 legend（若无 legend 且 ≥2 条线）
            ViewUtils.RefreshLegendFor(ax, ancestor(obj.Grid_, 'figure'));
        end
    end
end
