classdef TransferFunctionView < handle
%TRANSFERFUNCTIONVIEW  Hollow L3 mediator for FRF frequency-domain analysis.
%   Fixed 3-axes layout (Amp / Phase / Corr) with synchronized cursors.
%   Instantiates CursorComponent per axes, proxies events to Presenter.

    events
        BrowseClicked
        ImportButtonClicked
        ClearAllClicked
        CurveSelectionChanged   % struct('row', N)
        CursorSync              % struct('freq', F, 'sourceAxes', N)
    end

    properties (SetAccess = private)
        Grid                % top uigridlayout
        CurveTableH         % uitable (simple checkbox + name)
        AmpAxes             % uiaxes
        PhaseAxes           % uiaxes
        CorrAxes            % uiaxes
    end

    properties (SetAccess = private)
        Path_               % selected folder/file path
        Toaster             % AsyncToaster (RAII)
        AmpCursor           % CursorComponent
        PhaseCursor         % CursorComponent
        CorrCursor          % CursorComponent
    end

    properties (Access = private)
        SuppressSync logical = false  % prevent sync loops
    end

    methods
        % ================================================================
        %  Construction
        % ================================================================

        function obj = TransferFunctionView(parent)
        %TRANSFERFUNCTIONVIEW  Build layout and instantiate L2 components.

            obj.Grid = uigridlayout(parent, [1 2], ...
                'ColumnWidth', {'22x', '78x'}, ...
                'Padding', [6 6 6 6], ...
                'ColumnSpacing', 6);

            obj.buildLeftPanel();
            obj.buildRightPanel();

        end

        function delete(obj)
        %DELETE  Destroy cursor components on teardown.
            if ~isempty(obj.AmpCursor)   && isvalid(obj.AmpCursor),   delete(obj.AmpCursor);   end
            if ~isempty(obj.PhaseCursor) && isvalid(obj.PhaseCursor), delete(obj.PhaseCursor); end
            if ~isempty(obj.CorrCursor)  && isvalid(obj.CorrCursor),  delete(obj.CorrCursor);  end
        end

        % ================================================================
        %  Path management
        % ================================================================

        function path = GetPath(obj)
            path = obj.Path_;
        end

        function SetPath(obj, path)
            obj.Path_ = path;
        end

        % ================================================================
        %  Curve list (called by Presenter)
        % ================================================================

        function SetCurveList(obj, names, checked)
        %SETCURVELIST  Populate the curve checkbox table.
            n = numel(names);
            if nargin < 3 || isempty(checked)
                checked = true(n, 1);
            end
            obj.CurveTableH.Data = table(checked(:), names(:), ...
                'VariableNames', {'选择', '曲线'});
        end

        function checked = GetCurveSelection(obj)
            data = obj.CurveTableH.Data;
            if isempty(data)
                checked = [];
            else
                checked = data.(1);
            end
        end

        % ================================================================
        %  Render API (called by Presenter)
        % ================================================================

        function RenderFrf(obj, curves)
        %RENDERFRF  Draw FRF curves on all three axes (skip Freq=0).
            obj.ClearPlots();
            nPlotted = 0;

            for i = 1:numel(curves)
                c = curves(i);
                mask = c.freq > 0;
                if ~any(mask), continue; end
                nPlotted = nPlotted + 1;

                semilogx(obj.AmpAxes, c.freq(mask), c.amp(mask), ...
                    'DisplayName', c.name);
                hold(obj.AmpAxes, 'on');

                semilogx(obj.PhaseAxes, c.freq(mask), c.phase(mask), ...
                    'DisplayName', c.name);
                hold(obj.PhaseAxes, 'on');

                semilogx(obj.CorrAxes, c.freq(mask), c.corr(mask), ...
                    'DisplayName', c.name);
                hold(obj.CorrAxes, 'on');
            end

            hold(obj.AmpAxes,   'off');
            hold(obj.PhaseAxes, 'off');
            hold(obj.CorrAxes,  'off');
            ylim(obj.CorrAxes, [0 1]);

            obj.RefreshLegends();
        end

        function ClearPlots(obj)
            ViewUtils.DeleteDataLines(obj.AmpAxes);
            ViewUtils.DeleteDataLines(obj.PhaseAxes);
            ViewUtils.DeleteDataLines(obj.CorrAxes);
            legend(obj.AmpAxes, 'off');
            legend(obj.PhaseAxes, 'off');
            legend(obj.CorrAxes, 'off');
        end

        % ================================================================
        %  Cursor sync (called by Presenter)
        % ================================================================

        function SyncCursorToFreq(obj, freq, excludeIdx)
        %SYNCCURSORTOFREQ  Move all cursors to a frequency (except source).
            obj.SuppressSync = true;
            if excludeIdx ~= 1, obj.AmpCursor.SetPosition(freq);   end
            if excludeIdx ~= 2, obj.PhaseCursor.SetPosition(freq); end
            if excludeIdx ~= 3, obj.CorrCursor.SetPosition(freq);  end
            obj.SuppressSync = false;
        end

        % ================================================================
        % ================================================================
        %  Public: Host-dispatched cursor motion (replaces registerCursorMotion)
        % ================================================================

        function ProcessMouseMotion(obj)
        %PROCESSMOUSEMOTION  Called by Host layer to drive cursor.
        %   Replaces direct fig.WindowButtonMotionFcn registration.
            obj.onCursorMotion();
        end

        %  Dialog / utility methods
        % ================================================================

        function RefreshLegends(obj)
            obj.refreshLegendFor(obj.AmpAxes);
            obj.refreshLegendFor(obj.PhaseAxes);
            obj.refreshLegendFor(obj.CorrAxes);
        end

        function SetCursorLabelFormatter(obj, idx, fcn)
        %SETCURSORLABELFORMATTER  Set label formatter for cursor by index.
        %   idx: 1=Amp, 2=Phase, 3=Corr
            switch idx
                case 1, if ~isempty(obj.AmpCursor),   obj.AmpCursor.LabelFormatterFcn   = fcn; end
                case 2, if ~isempty(obj.PhaseCursor), obj.PhaseCursor.LabelFormatterFcn = fcn; end
                case 3, if ~isempty(obj.CorrCursor),  obj.CorrCursor.LabelFormatterFcn  = fcn; end
            end
        end

        function ShowLoading(obj, msg)
            if nargin < 2, msg = '处理中...'; end
            fig = ancestor(obj.Grid, 'figure');
            obj.Toaster = AsyncToaster(fig, '请稍候', msg);
            drawnow limitrate;   % 确保弹窗在重计算前刷新到屏幕
        end

        function CloseLoading(obj)
            obj.Toaster = [];
        end

        function ShowError(obj, msg)
            fig = ancestor(obj.Grid, 'figure');
            uialert(fig, msg, '错误', 'Icon', 'error');
        end

        function ShowInfo(obj, msg)
            fig = ancestor(obj.Grid, 'figure');
            uialert(fig, msg, '提示', 'Icon', 'success');
        end
    end

    % ================================================================
    %  Private: construction helpers
    % ================================================================
    methods (Access = private)

        function buildLeftPanel(obj)
            left = uigridlayout(obj.Grid, [2 1], ...
                'RowHeight', {'1x', 36}, ...
                'RowSpacing', 6, ...
                'Padding', [0 0 0 0]);
            left.Layout.Column = 1;

            obj.CurveTableH = uitable(left, ...
                'ColumnName', {'选择', '曲线'}, ...
                'ColumnEditable', [true false], ...
                'ColumnWidth', {38, '1x'});
            obj.CurveTableH.Layout.Row = 1;
            obj.CurveTableH.Data = table(true(0,1), cell(0,1), ...
                'VariableNames', {'选择', '曲线'});
            obj.CurveTableH.CellEditCallback = @(s,e) obj.onCurveEdit(e);

            btns = uigridlayout(left, [1 3], ...
                'ColumnWidth', {'1x', '1x', '1x'}, ...
                'ColumnSpacing', 4, 'Padding', [0 0 0 0]);
            btns.Layout.Row = 2;
            uibutton(btns, 'push', 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'BrowseClicked'));
            uibutton(btns, 'push', 'Text', 'Import', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ImportButtonClicked'));
            uibutton(btns, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ClearAllClicked'));
        end

        function buildRightPanel(obj)
            plots = uigridlayout(obj.Grid, [3 1], ...
                'RowHeight', {'1x', '1x', '1x'}, ...
                'RowSpacing', 4, 'Padding', [0 0 0 0]);
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

            % Create CursorComponents (data-agnostic, log-X aware)
            obj.AmpCursor   = CursorComponent(obj.AmpAxes,   1);
            obj.PhaseCursor = CursorComponent(obj.PhaseAxes, 2);
            obj.CorrCursor  = CursorComponent(obj.CorrAxes,  3);

            % Wire cursor snap → cross-axis sync event
            addlistener(obj.AmpCursor,   'CursorSnapped', @(s,e) obj.onCursorSnapped(e));
            addlistener(obj.PhaseCursor, 'CursorSnapped', @(s,e) obj.onCursorSnapped(e));
            addlistener(obj.CorrCursor,  'CursorSnapped', @(s,e) obj.onCursorSnapped(e));
        end

        % ================================================================
        %  Private: callbacks
        % ================================================================

        function onCurveEdit(obj, e)
            notify(obj, 'CurveSelectionChanged', ...
                AppEventData(struct('row', e.Indices(1))));
        end

        function onCursorSnapped(obj, e)
        %ONCURSORSNAPPED  Forward cursor snap to Presenter for cross-axis sync.
            if obj.SuppressSync, return; end
            d = e.Data;
            notify(obj, 'CursorSync', ...
                AppEventData(struct('freq', d.x, 'sourceAxes', d.axesIdx)));
        end

        function onCursorMotion(obj)
        %ONCURSORMOTION  Drive whichever cursor the mouse is over.
        %   Uses getpixelposition(ax, true) for absolute figure-space hit-test.
            if obj.SuppressSync, return; end

            fig = ancestor(obj.Grid, 'figure');
            if isempty(fig), return; end
            cp = fig.CurrentPoint;

            axesList  = {obj.AmpAxes, obj.PhaseAxes, obj.CorrAxes};
            cursorList = {obj.AmpCursor, obj.PhaseCursor, obj.CorrCursor};

            for i = 1:3
                ax = axesList{i};
                if isempty(ax) || ~isvalid(ax), continue; end

                % Absolute pixel position in figure space
                absPos = getpixelposition(ax, true);
                ti = ax.TightInset;  % [left bottom right top]

                innerX = absPos(1) + ti(1);
                innerY = absPos(2) + ti(2);
                innerW = absPos(3) - ti(1) - ti(3);
                innerH = absPos(4) - ti(2) - ti(4);

                if cp(1) >= innerX && cp(1) <= innerX + innerW ...
                 && cp(2) >= innerY && cp(2) <= innerY + innerH
                    cursor = cursorList{i};
                    if isvalid(cursor)
                        cursor.UpdateFromMouse();
                    end
                    return
                end
            end

            % Not over any axes — hide all cursors
            for i = 1:3
                c = cursorList{i};
                if isvalid(c), c.Hide(); end
            end
        end
    end

    methods (Access = private)
        function refreshLegendFor(~, ax)
        %REFRESHLEGENDFOR  Show legend only when 2+ data lines exist.
            allLines = findobj(ax, 'Type', 'line');
            dataMask = arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), allLines);
            if sum(dataMask) >= 2
                legend(ax, allLines(dataMask), 'Interpreter', 'none', ...
                    'Location', 'northeast');
            else
                legend(ax, 'off');
            end
        end
    end
end
