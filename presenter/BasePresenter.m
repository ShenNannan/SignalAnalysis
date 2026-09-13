classdef BasePresenter < handle
% BasePresenter - Presenter 基类：Listener 与弹窗生命周期集中管理
%
% 子类通过 TrackListener 登记所有 addlistener 句柄，通过 TrackPopup
% 登记衍生弹窗句柄；delete() 遍历销毁，避免事件监听残留导致的僵尸对象
% 与孤儿窗口。SignalAnalysisApp 的 CloseRequestFcn 先 delete 各
% Presenter（触发本类 delete）再删除主窗。

    properties (Access = protected)
        Listeners = {}      % event.listener 句柄集合
        PopupFigures = {}   % 衍生弹窗句柄集合
    end

    methods (Access = protected)
        function TrackListener(obj, listener)
            obj.Listeners{end+1} = listener;
        end

        function TrackPopup(obj, fig)
            obj.PopupFigures{end+1} = fig;
        end
    end

    methods
        function delete(obj)
            for i = 1:numel(obj.Listeners)
                if ~isempty(obj.Listeners{i}) && isvalid(obj.Listeners{i})
                    delete(obj.Listeners{i});
                end
            end
            obj.Listeners = {};

            for i = 1:numel(obj.PopupFigures)
                if ~isempty(obj.PopupFigures{i}) && isvalid(obj.PopupFigures{i})
                    delete(obj.PopupFigures{i});
                end
            end
            obj.PopupFigures = {};
        end
    end
end
