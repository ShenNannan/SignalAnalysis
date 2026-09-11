classdef SelectionManager < handle
% SelectionManager - 选区管理
%
% 替代 star_end/qiege/qiegehuitui。handle class。
% 支持拖拽选区和手动输入。

    properties (SetAccess = private)
        Session         SessionData
        PlotCtrl        PlotController
        History_        cell        % 选区历史栈（用于撤销）
        DragStart_      double      % 拖拽起点（样本索引）
        IsDragging_     logical     % 是否正在拖拽
    end

    methods
        function obj = SelectionManager(session, plotCtrl)
        % SelectionManager 构造函数
        %
        % 输入：
        %   session  - SessionData
        %   plotCtrl - PlotController

            obj.Session = session;
            obj.PlotCtrl = plotCtrl;
            obj.History_ = {};
            obj.DragStart_ = 0;
            obj.IsDragging_ = false;
        end

        function OnMouseDown(obj, axesIdx, xPos)
        % OnMouseDown 鼠标按下，记录起点

            obj.DragStart_ = xPos;
            obj.IsDragging_ = true;

            % 显示起点线
            obj.PlotCtrl.HighlightRange(axesIdx, xPos, xPos, 'g');
        end

        function OnMouseUp(obj, axesIdx, xPos)
        % OnMouseUp 鼠标释放，完成选区

            if ~obj.IsDragging_
                return;
            end

            obj.IsDragging_ = false;

            startVal = min(obj.DragStart_, xPos);
            endVal = max(obj.DragStart_, xPos);

            % 转换为样本索引（使用第一个数据集的采样率）
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                sampleTime = ds.SampleTime;
                startRow = max(1, round(startVal / sampleTime));
                endRow = min(ds.RowCount, round(endVal / sampleTime));

                % 保存当前选区到历史
                obj.History_{end+1} = obj.Session.SelectionRange;

                % 更新选区
                obj.Session.SetSelection(startRow, endRow);
            end
        end

        function SetRange(obj, startRow, endRow)
        % SetRange 直接设置选区（从编辑框）

            % 保存当前选区到历史
            obj.History_{end+1} = obj.Session.SelectionRange;

            obj.Session.SetSelection(startRow, endRow);
        end

        function SegmentToRange(obj, startRow, endRow)
        % SegmentToRange 截取并压栈

            % 保存当前选区到历史
            obj.History_{end+1} = obj.Session.SelectionRange;

            obj.Session.SetSelection(startRow, endRow);
        end

        function UndoSegment(obj)
        % UndoSegment 恢复上一个选区

            if isempty(obj.History_)
                return;
            end

            prevRange = obj.History_{end};
            obj.History_(end) = [];

            % 恢复时直接设置，不再压栈
            obj.Session.SetSelection(prevRange(1), prevRange(2));
        end

        function tf = HasHistory(obj)
        % HasHistory 是否有可撤销的历史

            tf = ~isempty(obj.History_);
        end

        function duration = GetSelectionDuration(obj)
        % GetSelectionDuration 选区时长 (s)

            range = obj.Session.SelectionRange;
            if obj.Session.HasDataset()
                ds = obj.Session.GetDataset(1);
                duration = (range(2) - range(1)) * ds.SampleTime;
            else
                duration = 0;
            end
        end

        function range = GetSelectionRange(obj)
        % GetSelectionRange 当前选区 [startRow, endRow]

            range = obj.Session.SelectionRange;
        end
    end
end
