classdef TimeSeriesView < handle
%TIMESERIESVIEW  Hollow L3 mediator for time-series analysis.
%   Instantiates L2 components, proxies their events outward, and exposes
%   high-level render methods called by the Presenter. Contains zero
%   business logic and zero plot algorithms.

    % ---- Outward events (consumed by Presenter) ----
    events
        BrowseClicked
        ImportButtonClicked
        ClearAllClicked
        ExportClicked
        ExportExcelClicked
        ClearPlotClicked
        SpectrumClicked
        NormClicked
        CalcClicked
        AxesRemoveClicked

        % Proxied from ChannelTableComponent.ActionRequested
        ChannelCheckChanged     % struct('datasetIdx',..,'colIdx',..,'checked',..)
        InlineRenameDataset     % struct('datasetIdx',..,'newName',..)
        InlineRenameChannel     % struct('datasetIdx',..,'colIdx',..,'newName',..)
        SetSampleRateClicked    % struct('datasetIdx',..)
        SliceDialogClicked      % struct('datasetIdx',..,'colIdx',..)
        SliceResetClicked       % struct('datasetIdx',..,'colIdx',..)
        SetXAxisClicked         % struct('datasetIdx',..,'colIdx',..)
        ClearXAxisClicked       % struct('axesIdx',..)
        SetRightYAxisClicked    % struct('datasetIdx',..,'colIdx',..)
        ClearRightYAxisClicked  % struct('axesIdx',..)

        % Proxied from CursorComponent.CursorSnapped
        CursorMotion            % struct('axesIdx',..,'x',..,'y',..,'lineTag',..,'xDataIdx',..)

        % Axes focus change (for channel table auto-refresh)
        FocusChanged
    end

    % ---- L2 Component handles (SetAccess = private for safety) ----
    properties (SetAccess = private)
        Grid                % top-level uigridlayout
        GridMgr             % AxesGridComponent
        TableComp           % ChannelTableComponent
        CursorMap           % containers.Map axesIdx → CursorComponent
        FocusedAxes         double = 1
    end

    properties (Access = private)
        % Toolbar handles (for external read if needed)
        SpectrumDropdown
        NormDropdown
        Toaster             % AsyncToaster (RAII, auto-closes)
        AxesXChannelMap     % cell: per-axes X-channel ref (for linkaxes grouping)
        HighlightedAxes double = 0  % currently highlighted axes index (0 = none)
    end

    methods
        % ================================================================
        %  Construction
        % ================================================================
        function obj = TimeSeriesView(parent)
        %TIMESERIESVIEW  Build the full layout and instantiate L2 components.

            obj.AxesXChannelMap = {};
            obj.CursorMap = containers.Map('KeyType', 'double', ...
                                           'ValueType', 'any');

            % ---- Top grid: left panel | right panel ----
            obj.Grid = uigridlayout(parent, [1 2], ...
                'ColumnWidth', {'22x', '78x'}, ...
                'Padding', [6 6 6 6], ...
                'ColumnSpacing', 6);

            % ---- Left: table + buttons ----
            left = uigridlayout(obj.Grid, [2 1], ...
                'RowHeight', {'1x', 36}, ...
                'RowSpacing', 4, ...
                'Padding', [2 2 2 2]);
            left.Layout.Column = 1;

            obj.TableComp = ChannelTableComponent(left);
            obj.TableComp.GetTableHandle().Layout.Row = 1;

            obj.buildLeftButtons(left);

            % ---- Right: toolbar + axes grid ----
            right = uigridlayout(obj.Grid, [2 1], ...
                'RowHeight', {36, '1x'}, ...
                'RowSpacing', 4);
            right.Layout.Column = 2;

            obj.buildToolbar(right);

            % AxesGridComponent lives in the bottom-right cell
            axesParent = uigridlayout(right, [1 1], ...
                'RowHeight', {'1x'}, 'ColumnWidth', {'1x'}, ...
                'RowSpacing', 4, 'ColumnSpacing', 4, ...
                'Padding', 0);
            axesParent.Layout.Row = 2;

            obj.GridMgr = AxesGridComponent(axesParent, 'MaxAxes', 6);

            % ---- Wire L2 events ----
            obj.wireComponentEvents();

            % ---- Seed one default axes ----
            obj.GridMgr.AddAxes();

            % ---- Register global mouse motion for cursors ----

        end

        function delete(obj)
        %DELETE  Destroy all CursorComponent instances on teardown.
            keys = obj.CursorMap.keys;
            for k = 1:numel(keys)
                c = obj.CursorMap(keys{k});
                if isvalid(c), delete(c); end
            end
        end

        % ================================================================
        %  High-level render API (called by Presenter)
        % ================================================================

        function RenderWaveform(obj, axesIdx, xCell, yCell, labels, colors, rightYData)
        %RENDERWAVEFORM  Draw multiple channels onto a single axes.
        %   Supports dual-Y via rightYData (struct or []).
        %   Uses findobj-based cleanup to preserve CursorComponent handles.

            if nargin < 7, rightYData = []; end

            ax = obj.GetAxes(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            hasRightY = isstruct(rightYData) && isfield(rightYData, 'x') ...
                && ~isempty(rightYData.x);

            savedButtonDownFcn = ax.ButtonDownFcn;

            % --- Targeted cleanup: delete data lines only, preserve cursors ---
            ViewUtils.DeleteDataLines(ax);
            legend(ax, 'off');
            ax.YAxis(2).Visible = 'off';

            ax.ButtonDownFcn   = savedButtonDownFcn;
            ax.LineStyleOrder  = '-';
            ax.LineStyleOrderIndex = 1;
            ax.ColorOrderIndex = 1;
            ax.XLimMode = 'auto';
            ax.YLimMode = 'auto';
            ax.NextPlot = 'add';  % CRITICAL: prevent plot() from destroying cursor objects

            if hasRightY
                ax.YAxis(2).Visible = 'on';
                yyaxis(ax, 'left');
                ax.LineStyleOrder = '-';
                ax.LineStyleOrderIndex = 1;
                ax.ColorOrderIndex = 1;
                for c = 1:numel(yCell)
                    displayName = DataPreparationService.ShortLabel(labels{c});
                    h = plot(ax, xCell{c}, yCell{c}, ...
                        'Color', colors{c}, 'LineWidth', 1, ...
                        'LineStyle', '-', 'DisplayName', displayName, ...
                        'Tag', 'leftY');
                    h.ButtonDownFcn = @(s,e) obj.onAxesButtonDown(axesIdx, e);
                end

                yyaxis(ax, 'right');
                ax.LineStyleOrder = '--';
                ax.LineStyleOrderIndex = 1;
                ax.ColorOrderIndex = 1;
                for c = 1:numel(rightYData.x)
                    h = plot(ax, rightYData.x{c}, rightYData.y{c}, ...
                        'Color', rightYData.colors{c}, 'LineWidth', 1, ...
                        'LineStyle', '--', 'DisplayName', rightYData.labels{c}, ...
                        'Tag', 'rightY');
                    h.ButtonDownFcn = @(s,e) obj.onAxesButtonDown(axesIdx, e);
                end
                yyaxis(ax, 'left');
            else
                yyaxis(ax, 'left');
                ax.LineStyleOrder = '-';
                ax.LineStyleOrderIndex = 1;
                ax.ColorOrderIndex = 1;
                for c = 1:numel(yCell)
                    displayName = DataPreparationService.ShortLabel(labels{c});
                    h = plot(ax, xCell{c}, yCell{c}, ...
                        'Color', colors{c}, 'LineWidth', 1, ...
                        'LineStyle', '-', 'DisplayName', displayName, ...
                        'Tag', 'leftY');
                    h.ButtonDownFcn = @(s,e) obj.onAxesButtonDown(axesIdx, e);
                end
            end

            grid(ax, 'on');
            obj.refreshLegend(ax);
        end

        function ClearAxes(obj, axesIdx)
        %CLEARAXES  Clear data lines from a single axes (preserves cursors).
            ax = obj.GetAxes(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end
            ViewUtils.DeleteDataLines(ax);
            legend(ax, 'off');
            ax.YAxis(2).Visible = 'off';
            yyaxis(ax, 'left');
            grid(ax, 'on');
        end

        function ClearAllAxes(obj)
        %CLEARALLAXES  Clear all axes.
            for i = 1:obj.GridMgr.Count
                obj.ClearAxes(i);
            end
        end

        % ================================================================
        %  Axes state management (called by Presenter)
        % ================================================================

        function hAx = GetAxes(obj, axesIdx)
        %GETAXES  Return the uiaxes handle at the given index.
            hAx = obj.GridMgr.GetAxes(axesIdx);
        end

        function [xl, ylL, ylR] = GetAxesLimits(obj, axesIdx)
        %GETAXESLIMITS  Return axis limits without exposing the handle.
        %   xl   - [xmin xmax]
        %   ylL  - [ymin ymax] left Y
        %   ylR  - [ymin ymax] right Y (empty if not visible)
            hAx = obj.GridMgr.GetAxes(axesIdx);
            xl  = xlim(hAx);
            ylL = ylim(hAx);   % left Y (active side by default)
            ylR = [];
            if hAx.YAxis(2).Visible
                yyaxis(hAx, 'right');
                ylR = ylim(hAx);
                yyaxis(hAx, 'left');
            end
        end

        function n = AxesCount(obj)
        %AXESCOUNT  Return the current number of axes.
            n = obj.GridMgr.Count;
        end

        function UpdateAxisChannelState(obj, axIdx, xDsIdx, xColIdx, rightYList)
        %UPDATEAXISCHANNELSTATE  Cache X/rightY refs for linkaxes grouping.
        %   rightYList: cell of [datasetIdx, colIdx]
            while numel(obj.AxesXChannelMap) < axIdx
                obj.AxesXChannelMap{end+1} = [];
            end
            if ~isempty(xDsIdx)
                obj.AxesXChannelMap{axIdx} = [xDsIdx, xColIdx];
            else
                obj.AxesXChannelMap{axIdx} = [];
            end
            % Forward state to table component for menu rule evaluation
            obj.TableComp.UpdateXChannel(xDsIdx, xColIdx);
            obj.TableComp.UpdateRightY(rightYList);
        end

        function SetChannelTable(obj, rows)
        %SETCHANNELTABLE  Forward row data to the table component.
            obj.TableComp.SetRows(rows);
        end

        % ================================================================
        %  Cursor management (called by Presenter)
        % ================================================================

        function HideCursor(obj)
        %HIDECURSOR  Hide all cursors across all axes.
            keys = obj.CursorMap.keys;
            for k = 1:numel(keys)
                c = obj.CursorMap(keys{k});
                if isvalid(c), c.Hide(); end
            end
        end

        function SetCursorLabelFormatter(obj, axesIdx, fcn)
        %SETCURSORLABELFORMATTER  Set the label formatter for a cursor.
            if obj.CursorMap.isKey(axesIdx)
                cursor = obj.CursorMap(axesIdx);
                cursor.LabelFormatterFcn = fcn;
            end
        end

        % ================================================================
        %  Loading / Error / Info dialogs
        % ================================================================

        function ShowLoading(obj, msg)
        %SHOWLOADING  Show a blocking progress dialog (RAII).
            if nargin < 2, msg = '处理中...'; end
            fig = ancestor(obj.Grid, 'figure');
            obj.Toaster = AsyncToaster(fig, '请稍候', msg);
            drawnow limitrate;   % 确保弹窗在重计算前刷新到屏幕
        end

        function UpdateLoading(obj, msg, fraction)
        %UPDATELOADING  Update the progress dialog message / fraction.
            if ~isempty(obj.Toaster) && isvalid(obj.Toaster)
                if nargin < 3
                    obj.Toaster.Update(msg);
                else
                    obj.Toaster.Update(msg, fraction);
                end
            end
        end

        function CloseLoading(obj)
        %CLOSELOADING  Close the progress dialog (also auto-closes on delete).
            obj.Toaster = [];  % delete triggers RAII close
        end

        function ShowError(obj, msg)
        %SHOWERROR  Show an error alert dialog.
            fig = ancestor(obj.Grid, 'figure');
            uialert(fig, msg, '错误', 'Icon', 'error');
        end

        function ShowInfo(obj, msg)
        %SHOWINFO  Show an info alert dialog.
            fig = ancestor(obj.Grid, 'figure');
            uialert(fig, msg, '提示', 'Icon', 'success');
        end

        % ================================================================
        %  Axes accessors (L3 — read-only, no class-name leakage)
        % ================================================================

        function n = GetAxesCount(obj)
        %GETAXESCOUNT  Number of active axes in the grid.
            n = obj.GridMgr.Count;
        end

        function hAx = GetAxesHandle(obj, idx)
        %GETAXESHANDLE  Return uiaxes handle at given index.
            hAx = obj.GridMgr.GetAxes(idx);
        end

        function idx = GetFocusedAxes(obj)
        %GETFOCUSEDAXES  Last-clicked axes index (1-based).
            idx = obj.FocusedAxes;
        end

        % ================================================================
        %  Macro-level dialog helpers (L3, no business logic)
        % ================================================================

        function result = ShowSliceRangeDialog(~, colName, totalRows, currentStart, currentLen)
        %SHOWSLICERANGEDIALOG  Ask user for slice range. Returns [start, len] or [].
            prompt = {sprintf('通道 %s（共 %d 行）\n起始行:', colName, totalRows), ...
                      '切片长度:'};
            dlgTitle = '设置切片范围';
            defaults = {num2str(currentStart), num2str(currentLen)};
            answer = inputdlg(prompt, dlgTitle, [1 40], defaults);
            if isempty(answer) || any(cellfun(@isempty, answer))
                result = []; return
            end
            result = [str2double(answer{1}), str2double(answer{2})];
            if any(isnan(result))
                result = [];
            end
        end

        % ShowSampleRateDialog — moved below with two-output signature

        function SetNormValue(obj, normMode)
        %SETNORMVALUE  Update the Norm dropdown to reflect session state.
            modeMap = containers.Map( ...
                {'none','minmax','zscore','meanzero'}, ...
                {'None','Min-Max','Z-Score','Mean Zero'});
            if modeMap.isKey(normMode)
                obj.NormDropdown.Value = modeMap(normMode);
            end
        end

        % ================================================================
        %  File dialog helpers (L3, no business logic)
        % ================================================================

        function [file, path] = ShowSaveDialog(~, filter, title, defaultName)
        %SHOWSAVEDIALOG  Native file-save dialog. Returns (file, path) or (0, 0).
            [file, path] = uiputfile(filter, title, defaultName);
        end

        function [answer, ok] = ShowSampleRateDialog(~, dsName, defaultVal)
        %SHOWSAMPLERATEDIALOG  Prompt for sample rate via inputdlg.
            if nargin < 3, defaultVal = ''; end
            if isnumeric(defaultVal), defaultVal = num2str(defaultVal); end
            answer = []; ok = false;
            dlg = inputdlg({sprintf('数据集:%s\n采样率 (Hz):', dsName)}, ...
                '设置采样率', [1 40], {defaultVal});
            if isempty(dlg), return; end
            v = str2double(dlg{1});
            if ~isnan(v) && v > 0
                answer = v; ok = true;
            end
        end

        function mode = GetSpectrumMode(obj)
        %GETSPECTRUMMODE  Read the spectrum dropdown value ('FFT' or 'PSD').
            mode = obj.SpectrumDropdown.Value;
        end

        function props = GetAxesLineProperties(obj, axesIdx)
        %GETAXESLINEPROPERTIES  Read visual properties of data lines on an axes.
        %   Returns struct array with fields: Color, LineStyle, DisplayName, IsRightY.
            props = struct('Color',{},'LineStyle',{},'DisplayName',{},'IsRightY',{});
            hAx = obj.GridMgr.GetAxes(axesIdx);
            if isempty(hAx) || ~isvalid(hAx), return; end

            allLines = findobj(hAx, 'Type', 'line');
            idx = 0;
            for k = 1:numel(allLines)
                ln = allLines(k);
                if strcmp(ln.Tag, 'cursor'), continue; end
                idx = idx + 1;
                props(idx).Color      = ln.Color;
                props(idx).LineStyle  = ln.LineStyle;
                props(idx).DisplayName = ln.DisplayName;
                props(idx).IsRightY   = strcmp(ln.Tag, 'rightY');
            end
        end

        % ================================================================
        %  Popup factory methods (L3: UI creation, no business logic)
        % ================================================================

        function h = CreateSpectrumPopup(~)
        %CREATESPECTRUMPOPUP  Create FFT/PSD popup skeleton.
        %   Returns struct(fig, axTime, axFreq). Presenter fills data.

            fig = uifigure('Name', 'Spectrum Analysis', ...
                'NumberTitle', 'off', 'Position', [200 150 900 720]);

            g = uigridlayout(fig, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [6 6 6 6], 'RowSpacing', 4);

            axTime = uiaxes(g);
            yyaxis(axTime, 'right'); cla(axTime); axTime.YAxis(2).Visible = 'off';
            yyaxis(axTime, 'left');  cla(axTime);
            axTime.Layout.Row = 1;

            axFreq = uiaxes(g);
            yyaxis(axFreq, 'right'); cla(axFreq); axFreq.YAxis(2).Visible = 'off';
            yyaxis(axFreq, 'left');  cla(axFreq);
            axFreq.Layout.Row = 2;

            h = struct('fig', fig, 'axTime', axTime, 'axFreq', axFreq);
        end

        function h = CreateCalcDialog(~, channelList)
        %CREATECALCDIALOG  Create channel-operation dialog skeleton.
        %   Returns struct with all UI handles. Presenter wires callbacks.

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
            btnOk     = uibutton(btnGrid, 'push', 'Text', '确定');
            btnCancel = uibutton(btnGrid, 'push', 'Text', '取消');

            h = struct('fig', fig, ...
                       'opPopup', opPopup, 'popupA', popupA, 'popupB', popupB, ...
                       'editA1', editA1, 'editA2', editA2, ...
                       'editB1', editB1, 'editB2', editB2, ...
                       'winLabel', winLabel, 'editWin', editWin, ...
                       'editName', editName, ...
                       'btnOk', btnOk, 'btnCancel', btnCancel);
        end

        function fig = CreateExportFigure(~, name)
        %CREATEEXPORTFIGURE  Create a legacy figure for export.
            fig = figure('Name', name, 'NumberTitle', 'off');
        end

        % ================================================================
        %  Legend utilities
        % ================================================================

        function RefreshLegends(obj)
        %REFRESHLEGENDS  Rebuild legends for all axes.
            for i = 1:obj.GridMgr.Count
                ax = obj.GridMgr.GetAxes(i);
                if ~isempty(ax) && isvalid(ax)
                    obj.refreshLegend(ax);
                end
            end
        end
    end

    % ================================================================
    %  Public: Host-dispatched cursor motion
    % ================================================================
    methods
        function ProcessMouseMotion(obj)
        %PROCESSMOUSEMOTION  Called by Host layer to drive cursor.
            obj.onCursorMotion();
        end
    end

    % ================================================================
    %  Private: construction helpers
    % ================================================================
    methods (Access = private)

        function buildLeftButtons(obj, parent)
            btns = uigridlayout(parent, [1 3], ...
                'ColumnWidth', {'1x', '1x', '1x'}, ...
                'ColumnSpacing', 4, 'Padding', [2 2 2 2]);
            btns.Layout.Row = 2;
            uibutton(btns, 'push', 'Text', 'Browse...', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'BrowseClicked'));
            uibutton(btns, 'push', 'Text', 'Import', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ImportButtonClicked'));
            uibutton(btns, 'push', 'Text', 'Clear All', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ClearAllClicked'));
        end

        function buildToolbar(obj, parent)
            sq = 28;
            tb = uigridlayout(parent, [1 12], ...
                'ColumnWidth', {sq, sq, sq, sq, 60, 48, '1x', 80, 44, 90, 44, 44}, ...
                'RowHeight', {sq}, 'ColumnSpacing', 4, 'Padding', [4 4 4 4]);
            tb.Layout.Row = 1;

            uibutton(tb, 'push', 'Text', '+', 'FontWeight', 'bold', 'FontSize', 14, ...
                'ButtonPushedFcn', @(s,e) obj.onAddAxes());
            uibutton(tb, 'push', 'Text', char(8722), 'FontSize', 14, ...
                'ButtonPushedFcn', @(s,e) obj.onRemoveAxes());
            uibutton(tb, 'push', 'Text', '||', ...
                'ButtonPushedFcn', @(s,e) obj.GridMgr.SetLayoutMode('single'));
            uibutton(tb, 'push', 'Text', '=', ...
                'ButtonPushedFcn', @(s,e) obj.GridMgr.SetLayoutMode('dual'));
            uibutton(tb, 'push', 'Text', 'Export', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ExportClicked'));
            uibutton(tb, 'push', 'Text', 'Clear', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'ClearPlotClicked'));

            uipanel(tb, 'Visible', 'off', 'BorderType', 'none');  % spacer

            obj.SpectrumDropdown = uidropdown(tb, ...
                'Items', {'FFT', 'PSD'}, 'Value', 'FFT', ...
                'Tooltip', '选择频谱分析模式');
            uibutton(tb, 'push', 'Text', '频谱', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'SpectrumClicked'));
            obj.NormDropdown = uidropdown(tb, ...
                'Items', {'None', 'Min-Max', 'Z-Score', 'Mean Zero'}, ...
                'Value', 'None');
            uibutton(tb, 'push', 'Text', 'Norm', ...
                'ButtonPushedFcn', @(s,e) obj.onNormClicked());
            uibutton(tb, 'push', 'Text', 'Calc', ...
                'ButtonPushedFcn', @(s,e) notify(obj, 'CalcClicked'));
        end

        % ================================================================
        %  Private: L2 event wiring
        % ================================================================

        function wireComponentEvents(obj)
        %WIRECOMPONENTEVENTS  Connect L2 component events to this mediator.

            % --- AxesGrid events ---
            addlistener(obj.GridMgr, 'AxesAdded',   @(s,e) obj.onAxesAdded(e));
            addlistener(obj.GridMgr, 'AxesRemoved', @(s,e) obj.onAxesRemoved(e));

            % --- ChannelTable events (generic action bus) ---
            addlistener(obj.TableComp, 'ActionRequested', ...
                @(s,e) obj.onTableAction(e));
        end

        % ================================================================
        %  Private: L2 event handlers
        % ================================================================

        function onAxesAdded(obj, e)
        %ONAXESADDED  Create a CursorComponent for the new axes.
            d   = e.Data;
            hAx = d.handle;
            idx = d.axesIdx;

            % Configure new axes
            yyaxis(hAx, 'right'); cla(hAx);
            hAx.YAxis(2).Visible = 'off';
            yyaxis(hAx, 'left');  cla(hAx);
            grid(hAx, 'on');
            hAx.Interactions = [zoomInteraction, regionZoomInteraction];

            % Attach cursor (L2 component, no data dependency)
            cursor = CursorComponent(hAx, idx);
            obj.CursorMap(idx) = cursor;

            % Proxy cursor event → View-level CursorMotion
            addlistener(cursor, 'CursorSnapped', ...
                @(s,e) notify(obj, 'CursorMotion', e));

            % Axes click → focus tracking
            hAx.ButtonDownFcn = @(s,e) obj.onAxesButtonDown(idx, e);

            obj.FocusedAxes = min(obj.FocusedAxes, idx);
            obj.highlightAxes(obj.FocusedAxes);
            notify(obj, 'FocusChanged');
        end

        function onAxesRemoved(obj, e)
        %ONAXESREMOVED  Destroy the cursor for the removed axes.
            idx = e.Data.axesIdx;

            % Remove cursor component
            if obj.CursorMap.isKey(idx)
                obj.CursorMap.remove(idx);
            end

            % Re-key remaining cursors (shift indices down)
            oldKeys = sort(cell2mat(obj.CursorMap.keys));
            newMap  = containers.Map('KeyType', 'double', 'ValueType', 'any');
            newIdx  = 0;
            for k = oldKeys
                newIdx = newIdx + 1;
                c = obj.CursorMap(k);
                c.SetAxesIdx(newIdx);   % keep event payload consistent
                newMap(newIdx) = c;
            end
            obj.CursorMap = newMap;

            obj.FocusedAxes = min(obj.FocusedAxes, obj.GridMgr.Count);
            obj.HighlightedAxes = 0;  % reset so highlightAxes applies to new index
            obj.highlightAxes(obj.FocusedAxes);
            notify(obj, 'FocusChanged');
            notify(obj, 'AxesRemoveClicked');
        end

        function onTableAction(obj, e)
        %ONTABLEACTION  Route ChannelTableComponent events to specific View events.
            d      = e.Data;
            action = d.action;

            switch action
                case 'checkChanged'
                    notify(obj, 'ChannelCheckChanged', e);
                case 'renameDataset'
                    notify(obj, 'InlineRenameDataset', e);
                case 'renameChannel'
                    notify(obj, 'InlineRenameChannel', e);
                case 'setSampleRate'
                    notify(obj, 'SetSampleRateClicked', e);
                case 'slice'
                    notify(obj, 'SliceDialogClicked', e);
                case 'sliceReset'
                    notify(obj, 'SliceResetClicked', e);
                case 'exportExcel'
                    notify(obj, 'ExportExcelClicked', e);
                case 'setXAxis'
                    notify(obj, 'SetXAxisClicked', e);
                case 'clearXAxis'
                    % Inject current focused axes index
                    d.axesIdx = obj.FocusedAxes;
                    notify(obj, 'ClearXAxisClicked', AppEventData(d));
                case 'setRightY'
                    notify(obj, 'SetRightYAxisClicked', e);
                case 'clearRightY'
                    d.axesIdx = obj.FocusedAxes;
                    notify(obj, 'ClearRightYAxisClicked', AppEventData(d));
            end
        end

        function onAxesButtonDown(obj, axesIdx, ~)
        %ONAXESBUTTONDOWN  Track which axes is focused and highlight it.
            obj.FocusedAxes = axesIdx;
            obj.highlightAxes(axesIdx);
            notify(obj, 'FocusChanged');
        end

        function onAddAxes(obj)
            obj.GridMgr.AddAxes();
        end

        function onRemoveAxes(obj)
            n = obj.GridMgr.Count;
            if n <= 1, return; end
            obj.GridMgr.RemoveAxes(n);
        end

        function onNormClicked(obj)
            mode = obj.NormDropdown.Value;
            notify(obj, 'NormClicked', AppEventData(struct('mode', mode)));
        end

        % ================================================================
        %  Private: cursor motion driver
        % ================================================================

        function onCursorMotion(obj)
        %ONCURSORMOTION  Route mouse position to the CursorComponent
        %   of whichever axes the pointer is currently over.
        %   Uses getpixelposition(ax, true) for absolute figure-space hit-test.

            fig = ancestor(obj.Grid, 'figure');
            if isempty(fig), return; end

            cp = fig.CurrentPoint;

            for i = 1:obj.GridMgr.Count
                ax = obj.GridMgr.GetAxes(i);
                if isempty(ax) || ~isvalid(ax), continue; end

                % Absolute pixel position in figure space (ignores uigridlayout nesting)
                absPos = getpixelposition(ax, true);
                ti = ax.TightInset;  % [left bottom right top]

                % Inner plot area in absolute figure coordinates
                innerX = absPos(1) + ti(1);
                innerY = absPos(2) + ti(2);
                innerW = absPos(3) - ti(1) - ti(3);
                innerH = absPos(4) - ti(2) - ti(4);

                if cp(1) >= innerX && cp(1) <= innerX + innerW ...
                 && cp(2) >= innerY && cp(2) <= innerY + innerH
                    if obj.CursorMap.isKey(i)
                        cursor = obj.CursorMap(i);
                        if isvalid(cursor)
                            cursor.UpdateFromMouse();
                        end
                    end
                    return
                end
            end
        end

        % ================================================================
        %  Private: utilities
        % ================================================================

        function refreshLegend(obj, ax) %#ok<INUSU>
        %REFRESHLEGEND  Show legend only when 2+ lines exist.
            allLines = findobj(ax, 'Type', 'line');
            dataMask = arrayfun(@(l) ~strcmp(l.Tag, 'cursor'), allLines);
            nData = sum(dataMask);
            if nData >= 2
                legend(ax, allLines(dataMask), 'Interpreter', 'none', ...
                    'Location', 'northwest');
            else
                legend(ax, 'off');
            end
        end

        function highlightAxes(obj, axesIdx)
        %HIGHLIGHTAXES  Visual border highlight on the focused axes.
            SEL_COLOR   = [0 0.45 0.74];
            SEL_WIDTH   = 1.5;
            DEF_COLOR   = [0.15 0.15 0.15];
            DEF_WIDTH   = 0.5;

            % Restore previous
            if obj.HighlightedAxes >= 1 && obj.HighlightedAxes <= obj.GridMgr.Count
                prev = obj.GridMgr.GetAxes(obj.HighlightedAxes);
                if ~isempty(prev) && isvalid(prev)
                    prev.XColor = DEF_COLOR;
                    prev.YColor = DEF_COLOR;
                    prev.LineWidth = DEF_WIDTH;
                end
            end

            % Highlight new
            if axesIdx >= 1 && axesIdx <= obj.GridMgr.Count
                hAx = obj.GridMgr.GetAxes(axesIdx);
                if ~isempty(hAx) && isvalid(hAx)
                    hAx.XColor = SEL_COLOR;
                    hAx.YColor = SEL_COLOR;
                    hAx.LineWidth = SEL_WIDTH;
                end
            end

            obj.HighlightedAxes = axesIdx;
        end
    end
end
