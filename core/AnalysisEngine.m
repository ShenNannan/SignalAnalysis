classdef AnalysisEngine < handle
% AnalysisEngine - 分析任务调度
%
% 支持多通道叠加分析。遍历 axes 的所有通道，逐个分析并叠加显示。

    properties (SetAccess = private)
        Session         SessionData
        PlotCtrl        PlotController
    end

    methods
        function obj = AnalysisEngine(session, plotCtrl)
            obj.Session = session;
            obj.PlotCtrl = plotCtrl;
        end

        function RunAnalysis(obj, axesIdx, ~)
        % RunAnalysis 对 axes 的所有通道绘制时域波形

            chans = obj.Session.GetAxesChannels(axesIdx);
            if isempty(chans)
                return;
            end

            obj.PlotCtrl.ClearAxes(axesIdx);

            colors = {'b', 'r', 'g', 'c', 'm', 'k'};

            hold(obj.PlotCtrl.GetAxesHandle(axesIdx), 'on');
            for c = 1:length(chans)
                chan = chans{c};
                signal = chan.Data;

                % 应用通道独立切片（优先）或全信号，支持环形缓冲
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    startRow = chan.SliceRange(1);
                    endRow = chan.SliceRange(2);
                else
                    startRow = 1;
                    endRow = length(signal);
                end
                nSig = length(signal);
                startRow = max(1, min(startRow, nSig));
                if endRow <= nSig
                    sig = signal(startRow:endRow);
                else
                    tail = signal(startRow:nSig);
                    head = signal(1:endRow - nSig);
                    sig = [tail; head];
                end
                sampleIdx = (0:length(sig)-1)';
                colorIdx = mod(c-1, length(colors)) + 1;
                chanColor = colors{colorIdx};

                obj.PlotCtrl.PlotTimeSeries(axesIdx, sampleIdx, sig, ...
                    'DisplayName', chan.Label, 'Color', chanColor);
            end
            hold(obj.PlotCtrl.GetAxesHandle(axesIdx), 'off');

            % 显示 legend（收集 DisplayName）
            ax = obj.PlotCtrl.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                lines = findobj(ax, 'Type', 'line');
                if ~isempty(lines)
                    lines = flipud(lines);
                    labels = cell(length(lines), 1);
                    for i = 1:length(lines)
                        dn = get(lines(i), 'DisplayName');
                        if isempty(dn)
                            labels{i} = sprintf('Ch%d', i);
                        else
                            labels{i} = dn;
                        end
                    end
                    leg = legend(ax, lines, labels{:}, 'Location', 'best');
                    set(leg, 'Interpreter', 'none');
                end
            end

            % 重绘后恢复归一化
            obj.ApplyNormalization(axesIdx);

            % 重新链接有数据的 axes
            obj.PlotCtrl.LinkAllAxes();
        end

        function RefreshAxes(obj, axesIdx)
        % RefreshAxes 刷新（选区变更后重算）

            chans = obj.Session.GetAxesChannels(axesIdx);
            if ~isempty(chans)
                analysisType = obj.Session.GetAxesAnalysisType(axesIdx);
                obj.RunAnalysis(axesIdx, analysisType);
            end
        end

        function RefreshAll(obj)
        % RefreshAll 刷新所有 axes

            for i = 1:obj.Session.AxesSlotCount
                chans = obj.Session.GetAxesChannels(i);
                if ~isempty(chans)
                    obj.RefreshAxes(i);
                end
            end
        end
    end

    methods (Access = private)
        function ApplyNormalization(obj, axesIdx)
        % ApplyNormalization 重绘后恢复归一化（读取 SessionData 中存储的参数）

            normMode = obj.Session.GetAxesNormMode(axesIdx);
            if strcmpi(normMode, 'none')
                return;
            end

            normParams = obj.Session.GetAxesNormParams(axesIdx);
            if ~isfield(normParams, 'channelStats') || isempty(normParams.channelStats)
                return;
            end

            obj.PlotCtrl.NormalizeAxes(axesIdx, normMode, normParams);
        end
    end
end
