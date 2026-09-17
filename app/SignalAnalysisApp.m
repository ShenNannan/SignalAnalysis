classdef SignalAnalysisApp < handle
%SIGNALANALYSISAPP  V2 integration entry point.
%   Wires TimeSeriesView (L3) + TimeSeriesPresenter (L4)
%   into the existing tabbed application shell.
%
%   Usage:
%     app = SignalAnalysisApp();
%
%   The TransferFunction tab still uses V1 components until its
%   own V2 refactoring is complete.

    properties (SetAccess = private)
        Fig                         % uifigure
        TabGroup                    % uitabgroup
        StatusBar                   % uilabel
        TimeSeriesView              % TimeSeriesView
        TransferFunctionView        % TransferFunctionView
        TimeSeriesPresenter         % TimeSeriesPresenter
        TransferFunctionPresenter   % TransferFunctionPresenter
    end

    properties (Access = private)
        PendingLegendRefresh logical = false
    end

    methods
        function obj = SignalAnalysisApp()
        %SIGNALANALYSISAPP  Build the full application shell.

            obj.Fig = uifigure( ...
                'Name', 'Signal Analysis Toolbox (V2)', ...
                'Position', [100 100 1200 700], ...
                'CloseRequestFcn', @(s,e) obj.onClose(), ...
                'WindowButtonMotionFcn', @(s,e) obj.onMouseMoved());

            mainGrid = uigridlayout(obj.Fig, [2 1], ...
                'RowHeight', {'1x', 24}, ...
                'ColumnWidth', {'1x'}, ...
                'Padding', [0 0 0 0], ...
                'RowSpacing', 0);

            obj.TabGroup = uitabgroup(mainGrid);
            obj.TabGroup.Layout.Row = 1;
            obj.TabGroup.SelectionChangedFcn = @(s,e) obj.onTabChanged();

            tabTS = uitab(obj.TabGroup, 'Title', '时域分析');
            tabTF = uitab(obj.TabGroup, 'Title', '传函分析');

            obj.StatusBar = uilabel(mainGrid, ...
                'Text', ' ', ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 10, ...
                'BackgroundColor', [0.94 0.94 0.94]);
            obj.StatusBar.Layout.Row = 2;

            % ---- V2 Time-Series stack ----
            obj.TimeSeriesView     = TimeSeriesView(tabTS);
            obj.TimeSeriesPresenter = TimeSeriesPresenter( ...
                obj.TimeSeriesView, SessionData(6), @obj.setStatusText);

            % ---- V2 Transfer-Function stack ----
            obj.TransferFunctionView = TransferFunctionView(tabTF);
            obj.TransferFunctionPresenter = TransferFunctionPresenter( ...
                obj.TransferFunctionView, @obj.setStatusText);

            SignalAnalysisApp.settleUI();
        end
    end

    methods (Access = private)

        function setStatusText(obj, txt)
            obj.StatusBar.Text = txt;
        end

        function onTabChanged(obj)
            obj.PendingLegendRefresh = true;
            drawnow;
        end

        function onMouseMoved(obj)
        %ONMOUSEMOVED  Unified cursor dispatch for both tabs.
        %   Host owns WindowButtonMotionFcn; dispatches to active view.
            % --- Legend refresh (deferred to mouse move) ---
            if obj.PendingLegendRefresh
                obj.PendingLegendRefresh = false;
                if isequal(obj.TabGroup.SelectedTab, obj.TabGroup.Children(2))
                    obj.TransferFunctionView.RefreshLegends();
                else
                    obj.TimeSeriesView.RefreshLegends();
                end
            end

            % --- Dispatch cursor motion to active tab view ---
            if isequal(obj.TabGroup.SelectedTab, obj.TabGroup.Children(2))
                obj.TransferFunctionView.ProcessMouseMotion();
            else
                obj.TimeSeriesView.ProcessMouseMotion();
            end
        end

        function onClose(obj)
            if ~isempty(obj.TransferFunctionPresenter)
                delete(obj.TransferFunctionPresenter);
                obj.TransferFunctionPresenter = [];
            end
            if ~isempty(obj.TimeSeriesPresenter)
                delete(obj.TimeSeriesPresenter);
                obj.TimeSeriesPresenter = [];
            end
            delete(obj.Fig);
        end
    end

    methods (Static, Access = private)
        function settleUI()
            for k = 1:40
                drawnow;
                pause(0.025);
            end
        end
    end
end