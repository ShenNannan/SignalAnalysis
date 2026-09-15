classdef SignalAnalysisApp < handle
% SignalAnalysisApp - 统一宿主：单窗口 + uitabgroup（时域分析/传函分析）
%
% 职责：
%   - 创建 uifigure 与顶层 uigridlayout，实例化两个 View（依赖注入）
%   - 持有全应用唯一状态栏（uilabel），更新回调注入 Presenter
%   - 接管 CloseRequestFcn：显式销毁各 Presenter（触发 BasePresenter.delete
%     清理 listener 与弹窗）后再删窗口，杜绝孤儿窗口与监听残留

    properties (SetAccess = private)
        Fig                         % uifigure
        TabGroup                    % uitabgroup
        StatusBar                   % uilabel 底部状态栏
        TimeSeriesView_             % TimeSeriesView
        TransferFunctionView_       % TransferFunctionView
        TimeSeriesPresenter_        % TimeSeriesPresenter
        TransferFunctionPresenter_  % TransferFunctionPresenter
    end

    properties (Access = private)
        PendingLegendRefresh_       % logical 页签切换后待刷新 legend
    end

    methods
        function obj = SignalAnalysisApp()
            obj.Fig = uifigure( ...
                'Name', 'Signal Analysis Toolbox', ...
                'Position', [100 100 1200 700], ...
                'CloseRequestFcn', @(src, evt) obj.OnClose(), ...
                'WindowButtonMotionFcn', @(src, evt) obj.OnMouseMoved());

            obj.PendingLegendRefresh_ = false;

            mainGrid = uigridlayout(obj.Fig, [2 1], ...
                'RowHeight', {'1x', 24}, ...
                'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], ...
                'RowSpacing', 0);

            obj.TabGroup = uitabgroup(mainGrid);
            obj.TabGroup.Layout.Row = 1;

            % 页签顺序固定：「时域分析」在前（默认选中）→ 启动直接进入时域分析
            tabTS = uitab(obj.TabGroup, 'Title', '时域分析');
            tabTF = uitab(obj.TabGroup, 'Title', '传函分析');

            % 隐藏页签内的 axes 首次可见前无法正确创建 legend，
            % 切换页签后刷新对应视图的 legend
            obj.TabGroup.SelectionChangedFcn = @(s, e) obj.OnTabChanged();

            obj.StatusBar = uilabel(mainGrid, ...
                'Text', ' ', ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 10, ...
                'BackgroundColor', [0.94 0.94 0.94]);
            obj.StatusBar.Layout.Row = 2;

            obj.TimeSeriesView_ = TimeSeriesView(tabTS);
            obj.TransferFunctionView_ = TransferFunctionView(tabTF);

            obj.TimeSeriesPresenter_ = TimeSeriesPresenter(obj.TimeSeriesView_, @obj.SetStatusText);
            obj.TransferFunctionPresenter_ = TransferFunctionPresenter(obj.TransferFunctionView_);

            SignalAnalysisApp.SettleUI();
        end

        function SetStatusText(obj, txt)
        % SetStatusText 更新状态栏文本（回调注入 Presenter）
            obj.StatusBar.Text = txt;
        end

        function SetTimeSeriesPresenter(obj, presenter)
            obj.TimeSeriesPresenter_ = presenter;
        end

        function SetTransferFunctionPresenter(obj, presenter)
            obj.TransferFunctionPresenter_ = presenter;
        end
    end

    methods (Static, Access = private)
        function SettleUI()
        % SettleUI 泵渲染队列直至 uigridlayout 布局完成
        % 部分会话中 uifigure 布局在事件循环空闲时才惰性处理，
        % 导致窗口已显示而控件仍停留默认位置（按钮"无显示"）。
            SETTLE_ITERATIONS = 40;   % 循环次数（经验值）
            SETTLE_PAUSE_SEC  = 0.025; % 每次暂停秒数
            for k = 1:SETTLE_ITERATIONS
                drawnow;
                pause(SETTLE_PAUSE_SEC);
            end
        end
    end

    methods (Access = private)
        function OnTabChanged(obj)
        % OnTabChanged 页签切换：可见性变化在回调返回后才传播，
        % 置标志待首次鼠标移动时刷新 legend（隐藏页签内创建的 legend 为空）
            obj.PendingLegendRefresh_ = true;
            drawnow;
        end

        function OnMouseMoved(obj)
        % OnMouseMoved 首次鼠标移动时补刷新页签切换后的 legend
            if ~obj.PendingLegendRefresh_
                return;
            end
            obj.PendingLegendRefresh_ = false;
            % Children(1)=时域分析, Children(2)=传函分析（按创建顺序）
            if isequal(obj.TabGroup.SelectedTab, obj.TabGroup.Children(2))
                obj.TransferFunctionView_.RefreshLegends();
            else
                obj.TimeSeriesView_.RefreshLegends();
            end
        end

        function OnClose(obj)
        % OnClose 用户关闭窗口：先销毁 Presenter，再删窗口
            if ~isempty(obj.TransferFunctionPresenter_)
                delete(obj.TransferFunctionPresenter_);
                obj.TransferFunctionPresenter_ = [];
            end
            if ~isempty(obj.TimeSeriesPresenter_)
                delete(obj.TimeSeriesPresenter_);
                obj.TimeSeriesPresenter_ = [];
            end
            delete(obj.Fig);
        end
    end
end
