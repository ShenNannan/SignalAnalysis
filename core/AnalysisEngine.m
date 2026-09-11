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

        function RunAnalysis(obj, axesIdx, analysisType)
        % RunAnalysis 对 axes 的所有通道执行分析并叠加显示

            chans = obj.Session.GetAxesChannels(axesIdx);
            if isempty(chans)
                return;
            end

            % 清除旧图
            obj.PlotCtrl.ClearAxes(axesIdx);

            % 获取选区
            range = obj.Session.SelectionRange;

            % 颜色循环
            colors = {'b', 'r', 'g', 'c', 'm', 'k'};

            % 遍历所有通道叠加
            hold(obj.PlotCtrl.GetAxesHandle(axesIdx), 'on');
            for c = 1:length(chans)
                chan = chans{c};
                signal = chan.Data;
                datasetIdx = chan.DatasetIdx;
                ds = obj.Session.GetDataset(datasetIdx);
                sampleTime = ds.SampleTime;
                sampleRate = ds.SampleRate;

                % 应用通道独立切片（优先）或全局选区
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    startRow = chan.SliceRange(1);
                    endRow = chan.SliceRange(2);
                else
                    startRow = max(1, range(1));
                    endRow = min(length(signal), range(2));
                end
                startRow = max(1, startRow);
                endRow = min(length(signal), endRow);
                sig = signal(startRow:endRow);
                sampleIdx = (startRow:endRow)';
                colorIdx = mod(c-1, length(colors)) + 1;
                chanColor = colors{colorIdx};

                switch lower(analysisType)
                    case 'time'
                        obj.PlotCtrl.PlotTimeSeries(axesIdx, sampleIdx, sig, ...
                            'DisplayName', chan.Label, 'Color', chanColor);

                    case 'fft'
                        result = SignalProcessor.ComputeFFT(sig, sampleTime);
                        obj.PlotCtrl.PlotFFT(axesIdx, result, ...
                            'DisplayName', chan.Label, 'Color', chanColor);

                    case 'psd'
                        result = SignalProcessor.ComputePSD(sig, sampleRate);
                        obj.PlotCtrl.PlotPSD(axesIdx, result, ...
                            'DisplayName', chan.Label, 'Color', chanColor);

                    case 'integral'
                        integrated = SignalProcessor.IntegrateSignal(sig, sampleTime);
                        obj.PlotCtrl.PlotTimeSeries(axesIdx, sampleIdx, integrated, ...
                            'DisplayName', [chan.Label ' Integral'], 'Color', chanColor);

                    case 'madsd'
                        madsd = SignalProcessor.ComputeMadsd(sig, sampleTime);
                        obj.PlotCtrl.SetTitle(axesIdx, ...
                            sprintf('%s MADSD = %.4f', chan.Label, madsd));
                end
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
        end

        function RefreshAxes(obj, axesIdx)
        % RefreshAxes 刷新（选区变更后重算）

            chans = obj.Session.GetAxesChannels(axesIdx);
            if ~isempty(chans)
                % 用当前显示的分析类型重跑（默认 time）
                obj.RunAnalysis(axesIdx, 'time');
            end
        end

        function RefreshAll(obj)
        % RefreshAll 刷新所有 axes

            for i = 1:length(obj.Session.AxesData_)
                chans = obj.Session.GetAxesChannels(i);
                if ~isempty(chans)
                    obj.RefreshAxes(i);
                end
            end
        end
    end
end
