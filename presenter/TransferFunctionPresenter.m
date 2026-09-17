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
                if ~isempty(folder)
                    obj.View.SetPath(folder);
                end
            end

            function OnImport(obj, ~, ~)
                path = obj.View.GetPath();
                if isempty(path)
                    obj.View.ShowError('请先选择数据路径');
                    return
                end

                obj.View.ShowLoading('导入 FRF 数据...');
                try
                    if isfolder(path)
                        [results, ~] = DataReaderFactory.Import(path);
                    elseif isfile(path)
                        [~, fname] = fileparts(path);
                        fileStructs = {struct('path', path, 'fname', fname)};
                        results = DataReaderFactory.ProcessFileGroup( ...
                            fileStructs, fileparts(path));
                    else
                        obj.View.CloseLoading();
                        obj.View.ShowError(['路径不存在: ' path]);
                        return
                    end

                    if isempty(results)
                        obj.View.CloseLoading();
                        obj.View.ShowError('未找到可导入的 FRF 数据');
                        return
                    end

                    curves = struct([]);
                    for i = 1:numel(results)
                        ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                        curves = [curves, DataReaderFactory.ExtractFrfCurves(ds)]; %#ok<AGROW>
                    end
                    obj.Curves_ = curves;

                    obj.View.SetCurveList({curves.name}, []);
                    obj.applySelection();
                    obj.View.CloseLoading();
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
            end
        end
    end
