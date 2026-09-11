classdef PlotController < handle
% PlotController - 统一绘图控制
%
% 替代28个重复回调。支持动态 axes 数量。
% 所有 PlotXxx 方法的 varargin 直接透传给底层 plot/semilogx。

    properties (SetAccess = private)
        ParentFigure    % Figure handle
        AxesContainer   % axes 所在的容器（uipanel 或 figure）
        AxesHandles_    cell    % axes handles
        AxesCount_      double  % 当前 axes 数量
        MaxAxes_        double  % axes 数量上限
        LayoutMode_     char    % 当前布局模式
    end

    methods
        function obj = PlotController(parentFigure, maxAxes, axesContainer)
        % PlotController 构造函数
        %
        % 输入：
        %   parentFigure  - Figure handle
        %   maxAxes       - int 最大 axes 数量，默认 6
        %   axesContainer - axes 所在容器（uipanel），可选

            if nargin < 2
                maxAxes = 6;
            end
            if nargin < 3
                axesContainer = parentFigure;
            end
            obj.ParentFigure = parentFigure;
            obj.AxesContainer = axesContainer;
            obj.MaxAxes_ = maxAxes;
            obj.AxesCount_ = 0;
            obj.AxesHandles_ = {};
            obj.LayoutMode_ = 'single';
        end

        function idx = AddAxes(obj)
        % AddAxes 新增 axes，返回索引

            if obj.AxesCount_ >= obj.MaxAxes_
                error('SignalAnalysis:PlotController:AxesLimitReached', ...
                    'Maximum axes count (%d) reached', obj.MaxAxes_);
            end

            obj.AxesCount_ = obj.AxesCount_ + 1;
            idx = obj.AxesCount_;

            % 创建 axes 在容器内
            ax = axes('Parent', obj.AxesContainer, 'Visible', 'on');

            % 扩展 handles
            while length(obj.AxesHandles_) < idx
                obj.AxesHandles_{end+1} = []; %#ok<AGROW>
            end
            obj.AxesHandles_{idx} = ax;

            % 重新布局
            obj.Relayout(obj.LayoutMode_);
        end

        function SetAxesClickCallback(obj, axesIdx, callback)
        % SetAxesClickCallback 设置 axes 点击回调（用于聚焦切换）

            ax = obj.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                set(ax, 'ButtonDownFcn', callback);
                % 使 axes 可点击
                set(ax, 'PickableParts', 'all', 'HitTest', 'on');
            end
        end

        function RemoveAxes(obj, axesIdx)
        % RemoveAxes 删除 axes

            if axesIdx < 1 || axesIdx > obj.AxesCount_
                return;
            end

            % 删除 axes handle
            if axesIdx <= length(obj.AxesHandles_) && ~isempty(obj.AxesHandles_{axesIdx})
                delete(obj.AxesHandles_{axesIdx});
            end
            obj.AxesHandles_(axesIdx) = [];
            obj.AxesCount_ = obj.AxesCount_ - 1;

            % 重新布局
            if obj.AxesCount_ > 0
                obj.Relayout(obj.LayoutMode_);
            end
        end

        function count = GetAxesCount(obj)
        % GetAxesCount 当前 axes 数量

            count = obj.AxesCount_;
        end

        function ax = GetAxesHandle(obj, axesIdx)
        % GetAxesHandle 获取 axes handle

            if axesIdx >= 1 && axesIdx <= length(obj.AxesHandles_)
                ax = obj.AxesHandles_{axesIdx};
            else
                ax = [];
            end
        end

        function PlotTimeSeries(obj, axesIdx, time, signal, varargin)
        % PlotTimeSeries 时域波形
        %
        % 输入：
        %   axesIdx - int axes 索引
        %   time    - [N×1 double] 时间轴
        %   signal  - [N×1 double] 信号
        %   varargin - 透传给 plot()

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            plot(ax, time, signal, varargin{:});
            xlabel(ax, 'Sample Index');
            ylabel(ax, 'Amplitude');
            grid(ax, 'on');
        end

        function PlotFFT(obj, axesIdx, fftResult, varargin)
        % PlotFFT 幅频曲线 semilogx

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            semilogx(ax, fftResult.Frequency, fftResult.Amplitude, varargin{:});
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, 'Amplitude');
            grid(ax, 'on');
        end

        function PlotPSD(obj, axesIdx, psdResult, varargin)
        % PlotPSD 功率谱 semilogx

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            semilogx(ax, psdResult.Frequency, 10*log10(psdResult.Power), varargin{:});
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, 'Power/Frequency (dB/Hz)');
            grid(ax, 'on');
        end

        function PlotBode(obj, axesIdx, freq, amp, phase)
        % PlotBode Bode 双子图

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            semilogx(ax, freq, amp);
            xlabel(ax, 'Frequency (Hz)');
            ylabel(ax, 'Magnitude (dB)');
            grid(ax, 'on');

            ax2 = obj.GetAxesHandle(axesIdx + 1);
            if ~isempty(ax2) && isvalid(ax2)
                semilogx(ax2, freq, phase);
                xlabel(ax2, 'Frequency (Hz)');
                ylabel(ax2, 'Phase (deg)');
                grid(ax2, 'on');
            end
        end

        function PlotNyquist(obj, axesIdx, realPart, imagPart)
        % PlotNyquist Nyquist 图

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            plot(ax, realPart, imagPart, 'b-', ...
                realPart, -imagPart, 'b--', 'LineWidth', 0.5);
            hold(ax, 'on');
            plot(ax, -1, 0, 'r+', 'MarkerSize', 10, 'LineWidth', 2);
            hold(ax, 'off');
            xlabel(ax, 'Real');
            ylabel(ax, 'Imaginary');
            grid(ax, 'on');
            axis(ax, 'equal');
        end

        function ClearAxes(obj, axesIdx)
        % ClearAxes 清除指定 axes

            ax = obj.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                cla(ax);
            end
        end

        function ClearAll(obj)
        % ClearAll 清除全部 axes

            for i = 1:obj.AxesCount_
                obj.ClearAxes(i);
            end
        end

        function SetXLimits(obj, axesIdx, range)
        % SetXLimits 设置 X 轴范围

            ax = obj.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                xlim(ax, range);
            end
        end

        function SetTitle(obj, axesIdx, titleStr)
        % SetTitle 设置标题

            ax = obj.GetAxesHandle(axesIdx);
            if ~isempty(ax) && isvalid(ax)
                title(ax, titleStr);
            end
        end

        function fig = ExportToFigure(obj, axesIndices)
        % ExportToFigure 导出指定 axes 到独立 figure

            fig = figure();
            n = length(axesIndices);
            for i = 1:n
                srcAx = obj.GetAxesHandle(axesIndices(i));
                if ~isempty(srcAx) && isvalid(srcAx)
                    ax = subplot(n, 1, i, 'Parent', fig);
                    copyobj(allchild(srcAx), ax);
                    xlabel(ax, get(get(srcAx, 'XLabel'), 'String'));
                    ylabel(ax, get(get(srcAx, 'YLabel'), 'String'));
                    title(ax, get(get(srcAx, 'Title'), 'String'));
                    grid(ax, 'on');
                end
            end
        end

        function HighlightRange(obj, axesIdx, startVal, stopVal, color)
        % HighlightRange 高亮选区

            if nargin < 5
                color = 'r';
            end

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end

            hold(ax, 'on');
            yl = ylim(ax);
            plot(ax, [startVal startVal], yl, [color '-'], 'LineWidth', 1.5);
            plot(ax, [stopVal stopVal], yl, [color '-'], 'LineWidth', 1.5);
            hold(ax, 'off');
        end

        function NormalizeAxes(obj, axesIdx, normMode, session)
        % NormalizeAxes 以当前 XLim 为参考窗口，对 axes 上所有通道做纵轴归一化
        %
        % 输入：
        %   axesIdx  - axes 索引
        %   normMode - 'none'|'minmax'|'zscore'|'meanzero'
        %   session  - SessionData 引用，用于获取通道数据

            ax = obj.GetAxesHandle(axesIdx);
            if isempty(ax) || ~isvalid(ax), return; end
            if strcmpi(normMode, 'none')
                return;
            end

            % 获取当前 XLim → 行号范围
            xl = xlim(ax);
            refStart = max(1, round(xl(1)));
            refEnd = round(xl(2));

            % 获取 axes 上所有 line 对象
            lines = findobj(ax, 'Type', 'line');
            if isempty(lines), return; end

            % 需要从 session 获取每个通道的原始数据来计算参考参数
            chans = session.GetAxesChannels(axesIdx);
            if isempty(chans), return; end

            % lines 是倒序的（最新画的在前面），需要反转
            lines = flipud(lines);

            for i = 1:min(length(lines), length(chans))
                chan = chans{i};
                signal = chan.Data;

                % 参考窗口范围（在原始数据坐标中）
                totalLen = length(signal);
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sliceStart = chan.SliceRange(1);
                else
                    sliceStart = 1;
                end

                % XLim 中的样本索引 → 信号内位置
                refStartLocal = max(1, refStart - sliceStart + 1);
                refEndLocal = min(totalLen, refEnd - sliceStart + 1);
                if refStartLocal >= refEndLocal
                    refStartLocal = 1;
                    refEndLocal = length(signal);
                end

                refSig = signal(refStartLocal:refEndLocal);

                % 获取当前显示的 YData
                yData = get(lines(i), 'YData');
                if isempty(yData), continue; end

                switch lower(normMode)
                    case 'minmax'
                        minY = min(refSig);
                        maxY = max(refSig);
                        if maxY - minY > 0
                            yData = (yData - minY) / (maxY - minY);
                        end
                    case 'zscore'
                        meanY = mean(refSig);
                        stdY = std(refSig);
                        if stdY > 0
                            yData = (yData - meanY) / stdY;
                        end
                    case 'meanzero'
                        meanY = mean(refSig);
                        yData = yData - meanY;
                end

                set(lines(i), 'YData', yData);
            end
        end

        function Relayout(obj, mode)
        % Relayout 布局切换
        %
        % 模式：'single' | 'dual' | 'triple' | 'quad'
        % 使用手动 Position 定位，兼容 uipanel 容器

            obj.LayoutMode_ = mode;

            n = obj.AxesCount_;
            if n == 0
                return;
            end

            % 确定行列数
            switch lower(mode)
                case 'single'
                    nRows = n; nCols = 1;
                case 'dual'
                    nRows = ceil(n / 2); nCols = 2;
                case 'triple'
                    nRows = ceil(n / 3); nCols = 3;
                case 'quad'
                    nRows = ceil(n / 2); nCols = 2;
                otherwise
                    nRows = n; nCols = 1;
            end

            % 手动计算每个 axes 的位置（归一化坐标）
            marginX = 0.05;
            marginY = 0.05;
            gapX = 0.02;
            gapY = 0.04;

            totalW = 1 - 2*marginX - (nCols-1)*gapX;
            totalH = 1 - 2*marginY - (nRows-1)*gapY;
            axW = totalW / nCols;
            axH = totalH / nRows;

            for i = 1:n
                ax = obj.AxesHandles_{i};
                if ~isempty(ax) && isvalid(ax)
                    col = mod(i-1, nCols);
                    row = floor((i-1) / nCols);

                    posX = marginX + col * (axW + gapX);
                    posY = 1 - marginY - (row+1)*axH - row*gapY;

                    set(ax, 'Units', 'normalized', ...
                        'Position', [posX, posY, axW, axH]);
                end
            end
        end
    end
end
