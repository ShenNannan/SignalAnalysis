classdef TimeSeriesPresenter < handle
%TIMESERIESPRESENTER  L4 business brain for time-series analysis.
%   Owns SessionData. Drives the View through high-level methods only.
%   Contains zero UI control class names (no uiaxes, uitable, etc.).
%
%   Dependency injection:
%     obj = TimeSeriesPresenter(viewHandle, sessionModel, statusCallback)

    properties (SetAccess = private)
        View                % TimeSeriesView (L3 mediator)
        Session             % SessionData (model)
        StatusCallback      % function_handle @(txt)
        Listeners           % cell of event.listener (for cleanup)
    end

    properties (Access = private)
        LastFocusedAxes  double = 0
        N_COLORS       double = 6
    end

    methods
        % ================================================================
        %  Construction / Destruction
        % ================================================================

        function obj = TimeSeriesPresenter(viewHandle, sessionModel, statusCallback)
        %TIMESERIESPRESENTER  Inject View + Model + optional status callback.

            arguments
                viewHandle      (1,1)
                sessionModel    (1,1)
                statusCallback  (1,1) function_handle = @(txt) []
            end

            obj.View           = viewHandle;
            obj.Session        = sessionModel;
            obj.StatusCallback = statusCallback;
            obj.Listeners      = {};

            obj.wireViewEvents();
            obj.RefreshChannelTable();
        end

        function delete(obj)
        %DELETE  Clean up all listeners.
            for i = 1:numel(obj.Listeners)
                if ~isempty(obj.Listeners{i}) && isvalid(obj.Listeners{i})
                    delete(obj.Listeners{i});
                end
            end
            obj.Listeners = {};
        end

        end

        % ================================================================
        %  Event wiring (private)
        % ================================================================

        methods (Access = private)

            function wireViewEvents(obj)
            %WIREVIEWEVENTS  Subscribe to every View event.
                v = obj.View;
                obj.track(addlistener(v, 'BrowseClicked',          @obj.OnBrowseFolder));
                obj.track(addlistener(v, 'ImportButtonClicked',    @obj.OnImportFiles));
                obj.track(addlistener(v, 'ClearAllClicked',        @obj.OnClearAll));
                obj.track(addlistener(v, 'ChannelCheckChanged',    @obj.OnChannelCheckChanged));
                obj.track(addlistener(v, 'AxesRemoveClicked',      @obj.OnAxesRemove));
                obj.track(addlistener(v, 'ExportClicked',          @obj.OnExportFigure));
                obj.track(addlistener(v, 'ExportExcelClicked',     @obj.OnExportExcel));
                obj.track(addlistener(v, 'ClearPlotClicked',       @obj.OnClearPlot));
                obj.track(addlistener(v, 'SpectrumClicked',        @obj.OnSpectrumClicked));
                obj.track(addlistener(v, 'NormClicked',            @obj.OnNormalize));
                obj.track(addlistener(v, 'CalcClicked',            @obj.OnCalcChannel));
                obj.track(addlistener(v, 'SliceDialogClicked',     @obj.OnSliceDialog));
                obj.track(addlistener(v, 'SliceResetClicked',      @obj.OnSliceReset));
                obj.track(addlistener(v, 'AxesClicked',            @obj.OnAxesClicked));
                obj.track(addlistener(v, 'SetSampleRateClicked',   @obj.OnSetSampleRate));
                obj.track(addlistener(v, 'InlineRenameChannel',    @obj.OnInlineRenameChannel));
                obj.track(addlistener(v, 'InlineRenameDataset',    @obj.OnInlineRenameDataset));
                obj.track(addlistener(v, 'SetXAxisClicked',        @obj.OnSetXAxis));
                obj.track(addlistener(v, 'ClearXAxisClicked',      @obj.OnClearXAxis));
                obj.track(addlistener(v, 'SetRightYAxisClicked',   @obj.OnSetRightYAxis));
                obj.track(addlistener(v, 'ClearRightYAxisClicked', @obj.OnClearRightYAxis));
                obj.track(addlistener(v, 'CursorMotion',           @obj.OnCursorMotion));
            end

            function track(obj, listener)
                obj.Listeners{end+1} = listener;
            end
        end

        % ================================================================
        %  Import / Clear
        % ================================================================

        methods (Access = private)

            function OnBrowseFolder(obj, ~, ~)
                startPath = obj.Session.GetLastPath(1);
                if isempty(startPath), startPath = pwd; end
                rootDir = ViewUtils.SelectFolder(startPath);
                if isempty(rootDir), return; end
                obj.Session.SetLastPath(1, rootDir);

                obj.View.ShowLoading('导入数据...');
                try
                    [results, ~] = DataReaderFactory.Import(rootDir);
                    obj.View.CloseLoading();
                    if isempty(results)
                        obj.View.ShowError('未找到可导入的数据文件');
                        return
                    end
                    obj.addResultsToSession(results);
                catch e
                    obj.View.CloseLoading();
                    obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
                end
            end

            function OnImportFiles(obj, ~, ~)
                startPath = obj.Session.GetLastPath(1);
                if isempty(startPath), startPath = pwd; end
                [~, filePaths] = ViewUtils.SelectFiles(startPath, ...
                    {'*.dat;*.csv;*.txt;*.xlsx;*.mat', ...
                     'Data Files (*.dat;*.csv;*.txt;*.xlsx;*.mat)'});
                if isempty(filePaths), return; end

                obj.View.ShowLoading('导入数据...');
                try
                    outputDir = fileparts(filePaths{1});
                    fileStructs = cell(1, numel(filePaths));
                    for k = 1:numel(filePaths)
                        [~, fname] = fileparts(filePaths{k});
                        fileStructs{k} = struct('path', filePaths{k}, 'fname', fname);
                    end
                    results = DataReaderFactory.ProcessFileGroup(fileStructs, outputDir);
                    obj.View.CloseLoading();
                    obj.Session.SetLastPath(1, outputDir);
                    obj.addResultsToSession(results);
                catch e
                    obj.View.CloseLoading();
                    obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
                end
            end

            function addResultsToSession(obj, results)
                existingPaths = obj.Session.DatasetPaths_;
                added = 0;
                for i = 1:numel(results)
                    if any(strcmp(results{i}.matPath, existingPaths))
                        continue
                    end
                    ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                    dsName = DataReaderFactory.LoadDatasetName(results{i}.matPath);
                    if isempty(dsName), dsName = results{i}.name; end
                    obj.Session.AddDataset(ds, dsName, results{i}.matPath);
                    added = added + 1;
                end
                obj.RefreshChannelTable();
                obj.StatusCallback(sprintf('  导入 %d 个数据集', added));
            end

            function OnClearAll(obj, ~, ~)
                obj.Session.ClearAllDatasets();
                obj.View.ClearAllAxes();
                obj.syncViewAxisState(obj.View.FocusedAxes);
                obj.RefreshChannelTable();
                obj.StatusCallback(' ');
            end
        end

        % ================================================================
        %  Channel check / render
        % ================================================================

        methods

            function OnChannelCheckChanged(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;
                    if d.colIdx == 0
                        ds = obj.Session.GetDataset(d.datasetIdx);
                        for c = 1:ds.ColumnCount
                            obj.setChannelChecked(axIdx, d.datasetIdx, c, d.checked);
                        end
                    else
                        obj.setChannelChecked(axIdx, d.datasetIdx, d.colIdx, d.checked);
                    end
                    obj.RenderAxes(axIdx);
                    obj.syncViewAxisState(axIdx);
                    obj.RefreshChannelTable();
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function RenderAxes(obj, axesIdx)
            %RENDERAXES  Prepare data and send to View for rendering.
            %   This is the single render entry point for one axes.

                chans = obj.Session.GetAxesChannels(axesIdx);
                if isempty(chans)
                    obj.View.ClearAxes(axesIdx);
                    return
                end

                % X-axis data
                [xDsIdx, xColIdx] = obj.Session.GetXChannel(axesIdx);
                hasXChannel = ~isempty(xDsIdx);
                if hasXChannel
                    xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
                else
                    xRaw = double.empty(0,1);
                end

                % Partition channels into left-Y vs right-Y vs X-only
                rightYRefs = obj.Session.GetRightYChannel(axesIdx);
                rightYSet  = containers.Map('KeyType', 'char', 'ValueType', 'logical');
                for ri = 1:numel(rightYRefs)
                    key = sprintf('%d_%d', rightYRefs{ri}.DatasetIdx, rightYRefs{ri}.ColIdx);
                    rightYSet(key) = true;
                end

                leftChans = {};
                for c = 1:numel(chans)
                    chan = chans{c};
                    chanKey = sprintf('%d_%d', chan.DatasetIdx, chan.ColIdx);
                    if rightYSet.isKey(chanKey), continue; end
                    if hasXChannel && chan.DatasetIdx == xDsIdx && chan.ColIdx == xColIdx
                        continue
                    end
                    leftChans{end+1} = chan; %#ok<AGROW>
                end

                % Norm params
                normMode   = obj.Session.GetAxesNormMode(axesIdx);
                normParams = obj.Session.GetAxesNormParams(axesIdx);

                % Use DataPreparationService for batch preparation
                [xCell, yCell, labels, colorList] = ...
                    DataPreparationService.PrepareMultiChannel( ...
                        leftChans, xRaw, hasXChannel, normMode, normParams, obj.N_COLORS);

                % Prepare right-Y channels
                rightYData = [];
                if ~isempty(rightYRefs)
                    rx = {}; ry = {}; rl = {}; rc = {};
                    for ri = 1:numel(rightYRefs)
                        ref = rightYRefs{ri};
                        ryChan = DataPreparationService.FindChannel( ...
                            chans, ref.DatasetIdx, ref.ColIdx);
                        if isempty(ryChan), continue; end

                        [ryX, ryY] = DataPreparationService.PreparePlotData( ...
                            ryChan.Data, xRaw, ryChan.SliceRange, hasXChannel);

                        rx{end+1} = ryX;                                          %#ok<AGROW>
                        ry{end+1} = ryY;                                          %#ok<AGROW>
                        rl{end+1} = DataPreparationService.ShortLabel(ryChan.Label); %#ok<AGROW>
                        rc{end+1} = DataPreparationService.ChannelColor( ...
                            ryChan.DatasetIdx, ryChan.ColIdx, obj.N_COLORS);       %#ok<AGROW>
                    end
                    rightYData = struct('x', {rx}, 'y', {ry}, 'labels', {rl}, 'colors', {rc});
                end

                obj.View.RenderWaveform(axesIdx, xCell, yCell, labels, colorList, rightYData);
            end

            function RefreshChannelTable(obj)
            %REFRESHCHANNELTABLE  Rebuild the hierarchical channel table.
                rows = struct('isParent', {}, 'parentIdx', {}, ...
                    'datasetIdx', {}, 'colIdx', {}, 'label', {}, ...
                    'datasetName', {}, 'checked', {});
                n = 0;

                for d = 1:obj.Session.DatasetCount
                    ds = obj.Session.GetDataset(d);
                    dsName = obj.Session.GetDatasetName(d);

                    n = n + 1;
                    parentRow = n;
                    rows(n).isParent    = true;
                    rows(n).parentIdx   = 0;
                    rows(n).datasetIdx  = d;
                    rows(n).colIdx      = 0;
                    rows(n).datasetName = dsName;
                    rows(n).label       = dsName;
                    parentChecked       = false;

                    for c = 1:ds.ColumnCount
                        n = n + 1;
                        rows(n).isParent   = false;
                        rows(n).parentIdx  = parentRow;
                        rows(n).datasetIdx = d;
                        rows(n).colIdx     = c;
                        rows(n).datasetName = dsName;

                        label = ds.GetColumnName(c);
                        [isChecked, sliceTag] = obj.getChannelState(d, c);
                        if ~isempty(sliceTag)
                            label = [label sliceTag]; %#ok<AGROW>
                        end
                        rows(n).label   = label;
                        rows(n).checked = isChecked;
                        if isChecked, parentChecked = true; end
                    end
                    rows(parentRow).checked = parentChecked;
                end

                obj.View.SetChannelTable(rows);
            end
        end

        % ================================================================
        %  Axes add/remove / clear
        % ================================================================

        methods (Access = private)

            function OnAxesRemove(obj, ~, ~)
                obj.Session.RemoveAxes(obj.View.AxesCount + 1);
                obj.syncViewAxisState(obj.View.FocusedAxes);
                obj.RefreshChannelTable();
            end

            function OnClearPlot(obj, ~, ~)
                obj.View.ClearAllAxes();
                for a = 1:obj.Session.AxesSlotCount
                    obj.Session.ClearAxes(a);
                end
                obj.syncViewAxisState(obj.View.FocusedAxes);
                obj.RefreshChannelTable();
            end

            function OnAxesClicked(obj, ~, evt)
            %ONAXESCLICKED  Layout toggle from toolbar.
                d = evt.Data;
                if isfield(d, 'mode')
                    % Layout mode change is handled by the View internally
                    % (AxesGridComponent layout). Presenter just re-renders.
                    obj.syncViewAxisState(obj.View.FocusedAxes);
                end
            end
        end

        % ================================================================
        %  X-axis / Right-Y axis management
        % ================================================================

        methods (Access = private)

            function OnSetXAxis(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;

                    chans = obj.Session.GetAxesChannels(axIdx);
                    if isempty(DataPreparationService.FindChannel(chans, d.datasetIdx, d.colIdx))
                        obj.View.ShowError('请先勾选该通道到当前 axes');
                        return
                    end

                    refs = obj.Session.GetRightYChannel(axIdx);
                    for i = 1:numel(refs)
                        if refs{i}.DatasetIdx == d.datasetIdx && refs{i}.ColIdx == d.colIdx
                            obj.View.ShowError('该通道已设为右 Y 轴，请先恢复');
                            return
                        end
                    end

                    obj.Session.SetXChannel(axIdx, d.datasetIdx, d.colIdx);
                    obj.syncViewAxisState(axIdx);
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();

                    dsName = obj.Session.GetDatasetName(d.datasetIdx);
                    ds = obj.Session.GetDataset(d.datasetIdx);
                    colName = ds.GetColumnName(d.colIdx);
                    obj.StatusCallback(sprintf('  Axes %d 横轴 → %s / %s', axIdx, dsName, colName));
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnClearXAxis(obj, ~, ~)
                try
                    axIdx = obj.View.FocusedAxes;
                    obj.Session.ClearXChannel(axIdx);
                    obj.syncViewAxisState(axIdx);
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();
                    obj.StatusCallback(sprintf('  Axes %d 横轴 → 默认', axIdx));
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnSetRightYAxis(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;

                    chans = obj.Session.GetAxesChannels(axIdx);
                    if isempty(DataPreparationService.FindChannel(chans, d.datasetIdx, d.colIdx))
                        obj.View.ShowError('请先勾选该通道到当前 axes');
                        return
                    end

                    [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                    if ~isempty(xDsIdx) && xDsIdx == d.datasetIdx && xColIdx == d.colIdx
                        obj.View.ShowError('该通道已设为横轴，请先恢复');
                        return
                    end

                    obj.Session.SetRightYChannel(axIdx, d.datasetIdx, d.colIdx);
                    obj.syncViewAxisState(axIdx);
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnClearRightYAxis(obj, ~, ~)
                try
                    axIdx = obj.View.FocusedAxes;
                    obj.Session.ClearRightYChannel(axIdx);
                    obj.syncViewAxisState(axIdx);
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function syncViewAxisState(obj, axIdx)
            %SYNCVIEWAXISSTATE  Push Session's axis state to View.
                [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                refs = obj.Session.GetRightYChannel(axIdx);
                rightYList = cell(1, numel(refs));
                for i = 1:numel(refs)
                    rightYList{i} = [refs{i}.DatasetIdx, refs{i}.ColIdx];
                end
                obj.View.UpdateAxisChannelState(axIdx, xDsIdx, xColIdx, rightYList);

                % Sync norm dropdown
                normMode = obj.Session.GetAxesNormMode(axIdx);
                obj.View.SetNormValue(normMode);
            end
        end

        % ================================================================
        %  Normalization
        % ================================================================

        methods (Access = private)

            function OnNormalize(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;
                    obj.Session.SetAxesNormMode(axIdx, d.mode);
                    if strcmpi(d.mode, 'none')
                        obj.Session.SetAxesNormParams(axIdx, struct());
                    else
                        obj.Session.SetAxesNormParams(axIdx, obj.computeNormParams(axIdx));
                    end
                    obj.RenderAxes(axIdx);
                catch e
                    obj.View.ShowError(e.message);
                end
            end
        end

        % ================================================================
        %  Slice / Rename / SampleRate
        % ================================================================

        methods (Access = private)

            function OnSliceDialog(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;
                    chans = obj.Session.GetAxesChannels(axIdx);
                    chanIdx = obj.findChannelIndex(chans, d.datasetIdx, d.colIdx);
                    if chanIdx == 0
                        obj.View.ShowError('请先勾选该通道到当前 axes');
                        return
                    end

                    chan = chans{chanIdx};
                    totalRows    = length(chan.Data);
                    currentRange = chan.SliceRange;
                    currentLen   = currentRange(2) - currentRange(1) + 1;
                    ds = obj.Session.GetDataset(d.datasetIdx);
                    colName = ds.GetColumnName(d.colIdx);

                    result = obj.View.ShowSliceRangeDialog(colName, totalRows, currentRange(1), currentLen);
                    if isempty(result), return; end
                    startRow = result(1);
                    segLen   = result(2);

                    if startRow > totalRows
                        obj.View.ShowError(sprintf('起点 %d 超过数据总行数 %d', startRow, totalRows));
                        return
                    end
                    if segLen > totalRows
                        obj.View.ShowError(sprintf('切片长度 %d 超过数据总行数 %d', segLen, totalRows));
                        return
                    end
                    endRow = startRow + segLen - 1;
                    if endRow > 2 * totalRows
                        obj.View.ShowError(sprintf('切片范围 %d~%d 超出环缓冲上限 %d', ...
                            startRow, endRow, 2 * totalRows));
                        return
                    end

                    obj.Session.SetChannelSlice(axIdx, chanIdx, startRow, endRow);
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnSliceReset(obj, ~, evt)
                try
                    d = evt.Data;
                    axIdx = obj.View.FocusedAxes;
                    chans = obj.Session.GetAxesChannels(axIdx);
                    chanIdx = obj.findChannelIndex(chans, d.datasetIdx, d.colIdx);
                    if chanIdx == 0, return; end

                    obj.Session.SetChannelSlice(axIdx, chanIdx, 1, length(chans{chanIdx}.Data));
                    obj.RenderAxes(axIdx);
                    obj.RefreshChannelTable();
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnInlineRenameChannel(obj, ~, evt)
                try
                    d = evt.Data;
                    ds = obj.Session.GetDataset(d.datasetIdx);
                    currentName = ds.GetColumnName(d.colIdx);
                    newName = strtrim(d.newName);
                    if isempty(newName) || newName == string(currentName), return; end
                    obj.RenameChannel(d.datasetIdx, d.colIdx, newName);
                    obj.RefreshChannelTable();
                    obj.RenderAxes(obj.View.FocusedAxes);
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnInlineRenameDataset(obj, ~, evt)
                try
                    d = evt.Data;
                    currentName = obj.Session.GetDatasetName(d.datasetIdx);
                    newName = strtrim(d.newName);
                    if isempty(newName) || newName == string(currentName), return; end
                    obj.Session.SetDatasetName(d.datasetIdx, newName);
                    matPath = obj.Session.GetDatasetPath(d.datasetIdx);
                    if ~isempty(matPath)
                        DataReaderFactory.UpdateDatasetNameInMat(matPath, newName);
                    end
                    obj.RefreshChannelTable();
                    obj.RenderAxes(obj.View.FocusedAxes);
                catch e
                    obj.View.ShowError(e.message);
                end
            end

            function OnSetSampleRate(obj, ~, evt)
                try
                    d = evt.Data;
                    ds = obj.Session.GetDataset(d.datasetIdx);
                    currentRate = ds.SampleRate;
                    dsName = obj.Session.GetDatasetName(d.datasetIdx);
                    default = '';
                    if ~isempty(currentRate), default = num2str(currentRate); end
                    newRate = obj.View.ShowSampleRateDialog(dsName, default);
                    if isempty(newRate), return; end
                    obj.SetSampleRate(d.datasetIdx, newRate);
                    obj.RefreshChannelTable();
                    obj.RenderAxes(obj.View.FocusedAxes);
                    obj.StatusCallback(sprintf('  %s 采样率 = %g Hz', dsName, newRate));
                catch e
                    obj.View.ShowError(e.message);
                end
            end
        end

        % ================================================================
        %  Cursor motion (L4 business logic)
        % ================================================================

        methods (Access = private)

            function OnCursorMotion(obj, ~, evt)
            %ONCURSORMOTION  Read channel values at cursor position.
                d = evt.Data;
                axIdx = d.axesIdx;

                chans = obj.Session.GetAxesChannels(axIdx);
                if isempty(chans), return; end

                xDataIdx = d.xDataIdx;
                readout  = {};

                for c = 1:numel(chans)
                    chan = chans{c};
                    [~, yVal] = DataPreparationService.ReadChannelAtCursor( ...
                        chan.Data, chan.SliceRange, xDataIdx, false);
                    if ~isnan(yVal)
                        readout{end+1} = struct('Label', chan.Label, 'Y', yVal); %#ok<AGROW>
                    end
                end

                % Format readout (delegate to a future L2 InfoBar component)
                lines = {};
                for r = 1:numel(readout)
                    lines{end+1} = sprintf('%s: %.6g', ...
                        readout{r}.Label, readout{r}.Y); %#ok<AGROW>
                end
                if ~isempty(lines)
                    obj.StatusCallback(strjoin(lines, '  |  '));
                end
            end
        end

        % ================================================================
        %  Export / Spectrum / Calc
        % ================================================================

        methods (Access = private)

            function OnExportFigure(obj, ~, ~)
            %ONEXPORTFIGURE  Export all axes to a standalone legacy figure.
            try
                n = obj.View.GetAxesCount();
                if n == 0, return; end
                fig = obj.View.CreateExportFigure('Export');

                for i = 1:n
                    ax = obj.View.GetAxesHandle(i);
                    sub = subplot(n, 1, i, 'Parent', fig);

                    allSrcLines = findobj(ax, 'Type', 'line');
                    leftSrc  = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'leftY'), allSrcLines));
                    rightSrc = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'rightY'), allSrcLines));
                    hasRightY = ~isempty(rightSrc);

                    if hasRightY
                        yyaxis(sub, 'left'); hold(sub, 'on');
                        subLeftLines = gobjects(0);
                        for k = 1:numel(leftSrc)
                            l = leftSrc(k);
                            h = plot(sub, l.XData, l.YData, ...
                                'Color', l.Color, 'LineStyle', l.LineStyle, ...
                                'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                                'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                            subLeftLines(end+1) = h; %#ok<AGROW>
                        end
                        hold(sub, 'off');
                        yyaxis(ax, 'left');
                        ylabel(sub, get(get(ax, 'YLabel'), 'String'));

                        yyaxis(sub, 'right'); hold(sub, 'on');
                        subRightLines = gobjects(0);
                        for k = 1:numel(rightSrc)
                            l = rightSrc(k);
                            h = plot(sub, l.XData, l.YData, ...
                                'Color', l.Color, 'LineStyle', l.LineStyle, ...
                                'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                                'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                            subRightLines(end+1) = h; %#ok<AGROW>
                        end
                        hold(sub, 'off');
                        yyaxis(ax, 'right');
                        ylabel(sub, get(get(ax, 'YLabel'), 'String'));
                        yyaxis(ax, 'left');

                        subAllLines = [subLeftLines, subRightLines];
                        yyaxis(sub, 'left');
                    else
                        hold(sub, 'on');
                        subAllLines = gobjects(0);
                        for k = 1:numel(allSrcLines)
                            l = allSrcLines(k);
                            h = plot(sub, l.XData, l.YData, ...
                                'Color', l.Color, 'LineStyle', l.LineStyle, ...
                                'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                                'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                            subAllLines(end+1) = h; %#ok<AGROW>
                        end
                        hold(sub, 'off');
                        ylabel(sub, get(get(ax, 'YLabel'), 'String'));
                    end

                    grid(sub, 'on');
                    title(sub, get(get(ax, 'Title'), 'String'));

                    [xDsIdx, xColIdx] = obj.Session.GetXChannel(i);
                    if ~isempty(xDsIdx)
                        dsName = obj.Session.DatasetPaths_{xDsIdx};
                        ds = obj.Session.GetDataset(xDsIdx);
                        xlabel(sub, sprintf('%s / %s', dsName, ds.GetColumnName(xColIdx)));
                    else
                        xlabel(sub, 'Sample Index');
                    end

                    if numel(subAllLines) > 1
                        legend(sub, subAllLines, 'Location', 'best', 'Interpreter', 'none');
                    end
                end
                obj.StatusCallback('  Figure 已导出');
            catch e
                obj.View.ShowError(e.message);
            end
            end

            function OnExportExcel(obj, ~, evt)
                d = evt.Data;
                ds = obj.Session.GetDataset(d.datasetIdx);
                dsName = obj.Session.GetDatasetName(d.datasetIdx);
                try
                    [file, path] = obj.View.ShowSaveDialog('*.xlsx', '导出 Excel', [dsName '.xlsx']);
                    if isequal(file, 0), return; end
                    obj.View.ShowLoading('导出中...');
                    T = table();
                    for c = 1:ds.ColumnCount
                        col = ds.GetColumn(c);
                        T.(ds.GetColumnName(c)) = col(1:min(end, 1e6));
                    end
                    writetable(T, fullfile(path, file));
                    obj.View.CloseLoading();
                    obj.StatusCallback(sprintf('  已导出 %s', file));
                catch e
                    obj.View.CloseLoading();
                    obj.View.ShowError(sprintf('导出失败: %s', e.message));
                end
            end

            function OnSpectrumClicked(obj, ~, ~)
            %ONSPECTRUMCLICKED  Open FFT/PSD spectrum popup.
            try
                mode = obj.View.GetSpectrumMode();
                analysisType = lower(mode);

                axIdx = obj.View.GetFocusedAxes();
                chans = obj.Session.GetAxesChannels(axIdx);
                if isempty(chans)
                    obj.View.ShowError('请先勾选通道到当前 axes');
                    return;
                end

                [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                hasXChannel = ~isempty(xDsIdx);
                xRaw = [];
                if hasXChannel
                    xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
                end

                h = obj.View.CreateSpectrumPopup();
                ax1 = h.axTime; ax2 = h.axFreq;
                hold(ax1, 'on'); hold(ax2, 'on');

                nPlotted = 0;
                for c = 1:length(chans)
                    chan = chans{c};
                    sampleRate = obj.EnsureSampleRate(chan.DatasetIdx);
                    if isempty(sampleRate) || isnan(sampleRate) || sampleRate <= 0
                        continue;
                    end

                    [sig, xSig] = ChannelOperations.SliceAndAlign(...
                        chan.Data, xRaw, chan.SliceRange, hasXChannel);
                    sig = obj.ApplyNorm(axIdx, c, sig);

                    chanColor = DataPreparationService.ChannelColor(chan.DatasetIdx, chan.ColIdx, 6);
                    chanLabel = chan.Label;
                    nPlotted = nPlotted + 1;
                    plot(ax1, xSig, sig, 'Color', chanColor, 'DisplayName', chanLabel);

                    switch analysisType
                        case 'fft'
                            [P1, freq] = SignalProcessor.ComputeFFTSingleSided(sig, sampleRate);
                            [freq, P1]  = SignalProcessor.SkipZeroFreq(freq, P1);
                            semilogx(ax2, freq, P1, 'Color', chanColor, 'DisplayName', chanLabel);
                        case 'psd'
                            [cumRms, freq, totalRms] = SignalProcessor.ComputeCumulativeRMS(sig, sampleRate);
                            label = sprintf('%s (RMS=%.4f)', chanLabel, totalRms);
                            [freq, cumRms] = SignalProcessor.SkipZeroFreq(freq, cumRms);
                            semilogx(ax2, freq, cumRms, 'Color', chanColor, 'DisplayName', label);
                    end
                end

                hold(ax1, 'off'); hold(ax2, 'off');
                set(ax2, 'XScale', 'log');
                if hasXChannel
                    dsName = obj.Session.DatasetPaths_{xDsIdx};
                    ds = obj.Session.GetDataset(xDsIdx);
                    xlabel(ax1, sprintf('%s / %s', dsName, ds.GetColumnName(xColIdx)));
                else
                    xlabel(ax1, 'Sample Index');
                end
                ylabel(ax1, 'Amplitude');
                title(ax1, 'Time Domain Signal');
                grid(ax1, 'on');
                xlabel(ax2, 'Frequency (Hz)');
                grid(ax2, 'on');
                if strcmpi(analysisType, 'fft')
                    ylabel(ax2, 'Amplitude');
                    title(ax2, 'FFT Single-Sided Amplitude Spectrum');
                else
                    ylabel(ax2, 'Cumulative RMS');
                    title(ax2, 'Cumulative RMS (from PSD)');
                end
                if nPlotted > 1
                    legend(ax1, 'Interpreter', 'none', 'Location', 'northwest');
                    legend(ax2, 'Interpreter', 'none', 'Location', 'northwest');
                end
            catch e
                obj.View.ShowError(e.message);
            end
            end

            function OnCalcChannel(obj, ~, ~)
            %ONCALCCHANNEL  Open channel-operation dialog.
                if obj.Session.DatasetCount == 0
                    obj.View.ShowError('请先导入数据');
                    return;
                end

                [channelList, channelMap] = obj.BuildChannelList();
                if isempty(channelList)
                    obj.View.ShowError('无可用通道');
                    return;
                end

                opKeys = {'add', 'sub', 'mul', 'div', ...
                           'diff', 'cumsum', 'abs', 'square', 'sqrt', ...
                           'log10', 'detrend', 'rms', 'smooth'};

                h = obj.View.CreateCalcDialog(channelList);
                dlg = h.fig;

                h.opPopup.ValueChangedFcn   = @(s, e) updateOpType();
                h.popupA.ValueChangedFcn    = @(s, e) updateOpType();
                h.btnOk.ButtonPushedFcn     = @(s, e) doCalc();
                h.btnCancel.ButtonPushedFcn = @(s, e) close(dlg);

                updateOpType();

                function updateOpType()
                    val = find(strcmp(h.opPopup.Value, h.opPopup.Items), 1);
                    if isempty(val), val = 1; end
                    key     = opKeys{val};
                    isDual   = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));
                    isSmooth = strcmp(key, 'smooth');

                    if isDual
                        h.popupB.Enable = 'on'; h.editB1.Enable = 'on'; h.editB2.Enable = 'on';
                    else
                        h.popupB.Enable = 'off'; h.editB1.Enable = 'off'; h.editB2.Enable = 'off';
                    end
                    if isSmooth
                        h.winLabel.Visible = 'on'; h.editWin.Visible = 'on';
                    else
                        h.winLabel.Visible = 'off'; h.editWin.Visible = 'off';
                    end

                    idxA = find(strcmp(h.popupA.Value, channelList), 1);
                    if isempty(idxA), idxA = 1; end
                    nameA = strrep(channelList{idxA}, ' > ', '_');
                    if isDual
                        idxB = find(strcmp(h.popupB.Value, channelList), 1);
                        if isempty(idxB), idxB = 1; end
                        nameB = strrep(channelList{idxB}, ' > ', '_');
                        ops = {'+', '-', '×', '÷'};
                        defaultName = sprintf('%s%s%s', nameA, ops{val}, nameB);
                    else
                        opNames = {'diff', 'cumsum', 'abs', 'sq', 'sqrt', 'log10', 'detrend', 'rms', 'smooth'};
                        defaultName = sprintf('%s(%s)', opNames{val - 4}, nameA);
                    end
                    if length(defaultName) > 63, defaultName = defaultName(1:63); end
                    h.editName.Value = defaultName;

                    if idxA <= size(channelMap, 1)
                        dsA = obj.Session.GetDataset(channelMap(idxA, 1));
                        h.editA2.Value = max(1, dsA.RowCount);
                    end
                    if isDual && idxB <= size(channelMap, 1)
                        dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                        h.editB2.Value = max(1, dsB.RowCount);
                    end
                end

                function doCalc()
                    try
                        val = find(strcmp(h.opPopup.Value, h.opPopup.Items), 1);
                        if isempty(val), val = 1; end
                        key   = opKeys{val};
                        isDual = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));

                        idxA = find(strcmp(h.popupA.Value, channelList), 1);
                        if isempty(idxA), idxA = 1; end
                        dsIdxA = channelMap(idxA, 1);
                        dsA    = obj.Session.GetDataset(dsIdxA);
                        dataA  = dsA.GetColumn(channelMap(idxA, 2));
                        a1     = max(1, round(h.editA1.Value));
                        aLen   = max(1, min(round(h.editA2.Value), size(dataA,1) - a1 + 1));
                        dataA  = dataA(a1 : a1 + aLen - 1);

                        params = struct();
                        if isDual
                            idxB = find(strcmp(h.popupB.Value, channelList), 1);
                            if isempty(idxB), idxB = 1; end
                            dsB   = obj.Session.GetDataset(channelMap(idxB, 1));
                            dataB = dsB.GetColumn(channelMap(idxB, 2));
                            b1    = max(1, round(h.editB1.Value));
                            bLen  = max(1, min(round(h.editB2.Value), size(dataB,1) - b1 + 1));
                            dataB = dataB(b1 : b1 + bLen - 1);
                            if length(dataA) ~= length(dataB)
                                obj.View.ShowError(sprintf('窗口长度不一致: A=%d, B=%d', length(dataA), length(dataB)));
                                return;
                            end
                        else
                            dataB = [];
                            switch key
                                case {'diff', 'cumsum'}
                                    params.sampleRate = obj.RequireSampleRateForCalc(dsIdxA);
                                case 'smooth'
                                    params.windowSize = round(h.editWin.Value);
                            end
                        end

                        if strcmp(key, 'rms')
                            rmsVal = ChannelOperations.Compute('rms', dataA, [], params);
                            obj.View.ShowInfo(sprintf('RMS = %.6g', rmsVal));
                            close(dlg);
                            return;
                        end

                        result = ChannelOperations.Compute(key, dataA, dataB, params);
                        resultName = strtrim(h.editName.Value);
                        if isempty(resultName)
                            resultName = sprintf('calc_%d', obj.Session.DatasetCount + 1);
                        end

                        tempDir = tempname; mkdir(tempDir);
                        matPath = DataReaderFactory.SaveStandard(result, {resultName}, tempDir, resultName, 'calc', 'calc');
                        newDs = DataReaderFactory.LoadStandard(matPath);
                        obj.Session.AddDataset(newDs, resultName, matPath);
                        obj.RefreshChannelTable();
                        close(dlg);
                    catch e
                        obj.View.ShowError(sprintf('运算失败:\n%s', e.message));
                    end
                end
            end

            % ================================================================
            %  Private utilities
            % ================================================================

            function setChannelChecked(obj, axIdx, datasetIdx, colIdx, checked)
                if checked
                    obj.Session.AddChannelToAxes(axIdx, datasetIdx, colIdx);
                else
                    obj.Session.RemoveChannelFromAxes(axIdx, datasetIdx, colIdx);
                end
            end

            function [isChecked, sliceTag] = getChannelState(obj, datasetIdx, colIdx)
            %GETCHANNELSTATE  Channel state + display tags for the table.
                isChecked = false;
                sliceTag  = '';
                axIdx = obj.View.FocusedAxes;
                chans = obj.Session.GetAxesChannels(axIdx);

                for sc = 1:numel(chans)
                    if chans{sc}.DatasetIdx == datasetIdx && chans{sc}.ColIdx == colIdx
                        isChecked = true;
                        sliceTag = DataPreparationService.BuildSliceTag( ...
                            chans{sc}.SliceRange, length(chans{sc}.Data));

                        % [X] / [R] tags
                        [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                        if ~isempty(xDsIdx) && xDsIdx == datasetIdx && xColIdx == colIdx
                            sliceTag = [sliceTag ' [X]'];
                        end
                        refs = obj.Session.GetRightYChannel(axIdx);
                        for ri = 1:numel(refs)
                            if refs{ri}.DatasetIdx == datasetIdx && refs{ri}.ColIdx == colIdx
                                sliceTag = [sliceTag ' [R]'];
                                break
                            end
                        end
                        break
                    end
                end
            end

            function idx = findChannelIndex(~, chans, datasetIdx, colIdx)
                idx = 0;
                for c = 1:numel(chans)
                    if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                        idx = c; return
                    end
                end
            end

            function SetSampleRate(obj, datasetIdx, newRate)
                obj.Session.SetSampleRate(datasetIdx, newRate);
                ds = obj.Session.GetDataset(datasetIdx);
                matPath = obj.Session.GetDatasetPath(datasetIdx);
                if ~isempty(matPath)
                    DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
                end
            end

            function RenameChannel(obj, datasetIdx, colIdx, newName)
                ds = obj.Session.GetDataset(datasetIdx);
                newNames = cell(1, ds.ColumnCount);
                for i = 1:ds.ColumnCount
                    newNames{i} = ds.GetColumnName(i);
                end
                newNames{colIdx} = newName;
                dsNew = ds.RebuildWithColumnNames(newNames);
                obj.Session.UpdateDataset(datasetIdx, dsNew);
                matPath = obj.Session.GetDatasetPath(datasetIdx);
                if ~isempty(matPath)
                    DataReaderFactory.UpdateColumnNamesInMeta(matPath, newNames);
                end
            end

            function normParams = computeNormParams(obj, axIdx)
            %COMPUTENORMPARAMS  Compute normalization stats from visible window.
                [xl, ~, ~] = obj.View.GetAxesLimits(axIdx);
                if isempty(xl)
                    normParams = struct(); return
                end

                [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                hasXChannel = ~isempty(xDsIdx);
                if hasXChannel
                    xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
                else
                    xRaw = double.empty(0,1);
                end

                chans = obj.Session.GetAxesChannels(axIdx);
                if isempty(chans)
                    normParams = struct(); return
                end

                channelStats = {};
                for i = 1:numel(chans)
                    chan = chans{i};
                    [sig, xSig] = ChannelOperations.SliceAndAlign( ...
                        chan.Data, xRaw, chan.SliceRange, hasXChannel);

                    if hasXChannel
                        mask = xSig >= xl(1) & xSig <= xl(2);
                        refSig = sig(mask);
                        if isempty(refSig), refSig = sig; end
                        s = struct('minY', min(refSig), 'maxY', max(refSig), ...
                                   'meanY', mean(refSig), 'stdY', std(refSig));
                    else
                        refStart = max(1, round(xl(1)));
                        refEnd   = round(xl(2));
                        sliceStart = 1;
                        if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                            sliceStart = chan.SliceRange(1);
                        end
                        s = ChannelOperations.ComputeStats(chan.Data, refStart, refEnd, sliceStart);
                    end
                    channelStats{end+1} = s; %#ok<AGROW>
                end

                normParams = struct('refWindow', xl, 'channelStats', {channelStats});
            end

            function sig = ApplyNorm(obj, axesIdx, chanIdx, sig)
            %APPLYNORM  Apply stored normalization to signal.
                normMode = obj.Session.GetAxesNormMode(axesIdx);
                if strcmpi(normMode, 'none'), return; end
                normParams = obj.Session.GetAxesNormParams(axesIdx);
                if ~isfield(normParams, 'channelStats') || isempty(normParams.channelStats)
                    return;
                end
                if chanIdx > length(normParams.channelStats), return; end
                stats = normParams.channelStats{chanIdx};
                switch lower(normMode)
                    case 'minmax'
                        if stats.maxY - stats.minY > 0
                            sig = (sig - stats.minY) / (stats.maxY - stats.minY);
                        end
                    case 'zscore'
                        if stats.stdY > 0
                            sig = (sig - stats.meanY) / stats.stdY;
                        end
                    case 'meanzero'
                        sig = sig - stats.meanY;
                end
            end

            function [channelList, channelMap] = BuildChannelList(obj)
            %BUILDCHANNELLIST  Flat channel list + (datasetIdx, colIdx) map.
                channelList = {};
                channelMap  = zeros(0, 2);
                for d = 1:obj.Session.DatasetCount
                    ds = obj.Session.GetDataset(d);
                    dsName = obj.Session.DatasetPaths_{d};
                    for c = 1:ds.ColumnCount
                        channelList{end+1} = sprintf('%s > %s', dsName, ds.GetColumnName(c)); %#ok<AGROW>
                        channelMap(end+1, :) = [d, c]; %#ok<AGROW>
                    end
                end
            end

            function sr = EnsureSampleRate(obj, datasetIdx)
            %ENSURESAMPLERATE  Prompt for sample rate if not yet set.
                sr = obj.Session.GetSampleRate(datasetIdx);
                if isempty(sr) || isnan(sr) || sr <= 0
                    dsName = obj.Session.DatasetPaths_{datasetIdx};
                    [answer, ok] = obj.View.ShowSampleRateDialog(dsName);
                    if ok && ~isempty(answer) && answer > 0
                        sr = answer;
                        obj.SetSampleRate(datasetIdx, sr);
                    else
                        sr = [];
                    end
                end
            end

            function sr = RequireSampleRateForCalc(obj, datasetIdx)
            %REQUIRESAMPLERATEFORCALC  Diff/cumsum prerequisite.
                sr = obj.EnsureSampleRate(datasetIdx);
                if isempty(sr) || isnan(sr) || sr <= 0
                    error('SignalAnalysis:TimeSeriesPresenter:MissingSampleRate', ...
                        '请先设置采样率');
                end
            end
        end
    end
