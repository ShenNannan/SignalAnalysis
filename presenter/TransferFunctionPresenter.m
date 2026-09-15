classdef TransferFunctionPresenter < BasePresenter
% TransferFunctionPresenter - 传函分析控制层（FRF 频响查看器）
%
% 桥接 TransferFunctionView 与 Service 层：
%   浏览/导入（FileExplorer + DataReaderFactory）→ ExtractFrfCurves → 渲染三图。
% 数据模型简单（Dataset + 曲线列表），不引入 SessionData。

    properties (SetAccess = private)
        View        % TransferFunctionView
        Curves_     % struct array：name/freq/amp/phase/corr
    end

    methods
        function obj = TransferFunctionPresenter(view)
            obj.View = view;
            obj.Curves_ = struct([]);

            obj.TrackListener(addlistener(view, 'BrowseClicked', @obj.OnBrowse));
            obj.TrackListener(addlistener(view, 'ImportButtonClicked', @obj.OnImport));
            obj.TrackListener(addlistener(view, 'CurveSelectionChanged', @obj.OnCurveSelection));
            obj.TrackListener(addlistener(view, 'ClearAllClicked', @obj.OnClearAll));
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
                return;
            end

            obj.View.ShowLoading('导入 FRF 数据...');
            try
                if isfolder(path)
                    [results, warnings] = DataReaderFactory.Import(path); %#ok<ASGLU>
                elseif isfile(path)
                    [~, fname] = fileparts(path);
                    fileStructs = {struct('path', path, 'fname', fname)};
                    results = DataReaderFactory.ProcessFileGroup(fileStructs, fileparts(path));
                else
                    obj.View.CloseLoading();
                    obj.View.ShowError(['路径不存在: ' path]);
                    return;
                end

                if isempty(results)
                    obj.View.CloseLoading();
                    obj.View.ShowError('未找到可导入的 FRF 数据');
                    return;
                end

                curves = struct([]);
                for i = 1:length(results)
                    ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                    curves = [curves, DataReaderFactory.ExtractFrfCurves(ds)]; %#ok<AGROW>
                end
                obj.Curves_ = curves;

                obj.View.SetCurveList({curves.name}, []);
                obj.ApplySelection();
                obj.View.CloseLoading();
            catch e
                obj.View.CloseLoading();
                obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
            end
        end

        function OnCurveSelection(obj, ~, ~)
            obj.ApplySelection();
        end

        function OnClearAll(obj, ~, ~)
            obj.Curves_ = struct([]);
            obj.View.SetCurveList({}, []);
            obj.View.ClearPlots();
            obj.View.SetPath('');
        end
    end

    methods (Access = private)
        function ApplySelection(obj)
        % ApplySelection 按勾选状态叠画三图
            if isempty(obj.Curves_)
                obj.View.ClearPlots();
                return;
            end
            checked = obj.View.GetCurveSelection();
            if numel(checked) ~= numel(obj.Curves_)
                return;
            end
            obj.View.RenderFrf(obj.Curves_(checked));
        end
    end
end
