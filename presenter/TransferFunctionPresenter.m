classdef TransferFunctionPresenter < handle
%TRANSFERFUNCTIONPRESENTER  L4 business brain for FRF analysis.
%   Owns the FRF curves. Drives the View through high-level methods only.
%   Handles cross-axis cursor synchronization.

    properties (SetAccess = private)
        View                % TransferFunctionView (L3 mediator)
        StatusCallback      % function_handle @(txt)
        Curves_             % struct array: name / freq / amp / phase / corr
        Listeners           % cell of event.listener
    end

    methods
        % ================================================================
        %  Construction / Destruction
        % ================================================================

        function obj = TransferFunctionPresenter(viewHandle, statusCallback)
            arguments
                viewHandle     (1,1)
                statusCallback (1,1) function_handle = @(txt) []
            end

            obj.View           = viewHandle;
            obj.StatusCallback = statusCallback;
            obj.Curves_        = struct([]);
            obj.Listeners      = {};

            obj.wireViewEvents();
        end

        function delete(obj)
            for i = 1:numel(obj.Listeners)
                if ~isempty(obj.Listeners{i}) && isvalid(obj.Listeners{i})
                    delete(obj.Listeners{i});
                end
            end
            obj.Listeners = {};
        end

        end

        % ================================================================
        %  Event handlers
        % ================================================================

        methods (Access = private)

            function wireViewEvents(obj)
                v = obj.View;
                obj.track(addlistener(v, 'BrowseClicked',         @obj.OnBrowse));
                obj.track(addlistener(v, 'ImportButtonClicked',   @obj.OnImport));
                obj.track(addlistener(v, 'CurveSelectionChanged', @obj.OnCurveSelection));
                obj.track(addlistener(v, 'ClearAllClicked',       @obj.OnClearAll));
                obj.track(addlistener(v, 'CursorSync',            @obj.OnCursorSync));
            end

            function track(obj, listener)
                obj.Listeners{end+1} = listener;
            end

            function OnBrowse(obj, ~, ~)
                startPath = obj.View.GetPath();
                if isempty(startPath) || ~exist(startPath, 'dir')
                    startPath = pwd;
                end
                folder = ViewUtils.SelectFolder(startPath);
                if isempty(folder), return; end
                obj.View.SetPath(folder);

                % Auto-import (same behavior as TimeSeries OnBrowseFolder)
                obj.View.ShowLoading('导入 FRF 数据...');
                try
                    [results, ~] = DataReaderFactory.Import(folder);
                    obj.View.CloseLoading();
                    if isempty(results)
                        obj.View.ShowError('未找到可导入的 FRF 数据');
                        return
                    end

                    curves = struct([]);
                    for i = 1:numel(results)
                        ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                        curves = [curves, DataReaderFactory.ExtractFrfCurves(ds)]; %#ok<AGROW>
                    end
                    obj.Curves_ = curves;

                    names = {curves.name};
                    obj.View.SetCurveList(names, false(numel(names), 1));
                    obj.applySelection();
                catch e
                    obj.View.CloseLoading();
                    obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
                end
            end

            function OnImport(obj, ~, ~)
                startPath = obj.View.GetPath();
                if isempty(startPath) || ~exist(startPath, 'dir')
                    startPath = pwd;
                end
                [~, filePaths] = ViewUtils.SelectFiles(startPath, ...
                    {'*.dat;*.csv;*.txt;*.xlsx;*.mat', ...
                     'Data Files (*.dat;*.csv;*.txt;*.xlsx;*.mat)'});
                if isempty(filePaths), return; end

                obj.View.ShowLoading('导入 FRF 数据...');
                try
                    outputDir = fileparts(filePaths{1});
                    fileStructs = cell(1, numel(filePaths));
                    for k = 1:numel(filePaths)
                        [~, fname] = fileparts(filePaths{k});
                        fileStructs{k} = struct('path', filePaths{k}, 'fname', fname);
                    end
                    results = DataReaderFactory.ProcessFileGroup(fileStructs, outputDir);
                    obj.View.CloseLoading();
                    obj.View.SetPath(outputDir);

                    if isempty(results)
                        obj.View.ShowError('未找到可导入的 FRF 数据');
                        return
                    end

                    curves = struct([]);
                    for i = 1:numel(results)
                        ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                        curves = [curves, DataReaderFactory.ExtractFrfCurves(ds)]; %#ok<AGROW>
                    end
                    obj.Curves_ = curves;

                    names = {curves.name};
                    obj.View.SetCurveList(names, false(numel(names), 1));
                    obj.applySelection();
                    obj.StatusCallback(sprintf('  导入 %d 条 FRF 曲线', numel(curves)));
                catch e
                    obj.View.CloseLoading();
                    obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
                end
            end

            function OnCurveSelection(obj, ~, ~)
                obj.applySelection();
            end

            function OnClearAll(obj, ~, ~)
                obj.Curves_ = struct([]);
                obj.View.SetCurveList({}, []);
                obj.View.ClearPlots();
                obj.View.SetPath('');
                obj.StatusCallback(' ');
            end

            function OnCursorSync(obj, ~, evt)
            %ONCURSORSYNC  Synchronize cursors across all three axes.
                d = evt.Data;
                obj.View.SyncCursorToFreq(d.freq, d.sourceAxes);
            end
        end

        methods (Access = private)

            function applySelection(obj)
            %APPLYSELECTION  Filter curves by checkbox state and render.
                if isempty(obj.Curves_)
                    obj.View.ClearPlots();
                    return
                end
                checked = obj.View.GetCurveSelection();
                if numel(checked) ~= numel(obj.Curves_)
                    return
                end
                obj.View.RenderFrf(obj.Curves_(checked));

                % Set cursor readout: Freq (Hz) + axis-specific Y unit
                obj.View.SetCursorLabelFormatter(1, ...
                    @(x, y) sprintf('Freq: %.4g Hz\nMag: %.3f dB', x, y));
                obj.View.SetCursorLabelFormatter(2, ...
                    @(x, y) sprintf('Freq: %.4g Hz\nPhase: %.3f deg', x, y));
                obj.View.SetCursorLabelFormatter(3, ...
                    @(x, y) sprintf('Freq: %.4g Hz\nCorr: %.4f', x, y));
            end
        end
    end
