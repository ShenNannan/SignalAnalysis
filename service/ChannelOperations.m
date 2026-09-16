classdef ChannelOperations
% ChannelOperations - 通道运算纯函数库
%
% 无状态、无 UI 依赖，所有方法均为 Static，可直接命令行调用与单元测试。

    methods (Static)
        function sig = ApplySlice(signal, startRow, endRow)
        % ApplySlice 环缓冲切片
        %
        % 输入：
        %   signal   - [N×1] 信号
        %   startRow - 起始行（1-based，自动钳制到 [1, N]）
        %   endRow   - 结束行（可超过数据长度 N，超出部分回绕到开头）
        %
        % 输出：
        %   sig - endRow≤N 时为 signal(startRow:endRow)，
        %         否则 [tail; head] 环形拼接

            if isempty(signal)
                sig = signal;
                return;
            end

            nSig = length(signal);
            startRow = max(1, min(round(startRow), nSig));
            endRow = round(endRow);
            if endRow <= nSig
                sig = signal(startRow:endRow);
            else
                tail = signal(startRow:nSig);
                head = signal(1:endRow - nSig);
                sig = [tail; head];
            end
        end

        function result = Compute(op, dataA, dataB, params)
        % Compute 通道运算分派
        %
        % 输入：
        %   op     - 运算关键字：'add'|'sub'|'mul'|'div'|'diff'|'cumsum'|
        %            'abs'|'square'|'sqrt'|'log10'|'detrend'|'rms'|'smooth'
        %   dataA  - 通道A 数据（列向量）
        %   dataB  - 通道B 数据（仅二元运算需要，可空）
        %   params - struct，可选字段 .sampleRate（diff/cumsum 需要）、
        %            .windowSize（smooth 需要）
        %
        % 输出：
        %   result - 运算结果；'rms' 返回标量

            if nargin < 4
                params = struct();
            end
            if nargin < 3
                dataB = [];
            end

            op = lower(op);
            dualOps = {'add', 'sub', 'mul', 'div'};
            unaryOps = {'diff', 'cumsum', 'abs', 'square', 'sqrt', ...
                        'log10', 'detrend', 'rms', 'smooth'};

            if any(strcmp(op, dualOps))
                if isempty(dataB)
                    error('SignalAnalysis:ChannelOperations:MissingOperand', ...
                        '二元运算 %s 需要通道B', op);
                end
                if length(dataA) ~= length(dataB)
                    error('SignalAnalysis:ChannelOperations:LengthMismatch', ...
                        '窗口长度不一致: A=%d, B=%d', length(dataA), length(dataB));
                end
                switch op
                    case 'add'
                        result = dataA + dataB;
                    case 'sub'
                        result = dataA - dataB;
                    case 'mul'
                        result = dataA .* dataB;
                    case 'div'
                        result = dataA ./ dataB;
                        result(dataB == 0) = NaN;
                end
            elseif any(strcmp(op, unaryOps))
                switch op
                    case 'diff'
                        result = diff(dataA) * ChannelOperations.RequireSampleRate(params);
                    case 'cumsum'
                        result = cumsum(dataA) / ChannelOperations.RequireSampleRate(params);
                    case 'abs'
                        result = abs(dataA);
                    case 'square'
                        result = dataA .^ 2;
                    case 'sqrt'
                        result = sqrt(abs(dataA));
                    case 'log10'
                        result = log10(abs(dataA) + eps);
                    case 'detrend'
                        result = detrend(dataA);
                    case 'rms'
                        result = sqrt(mean(dataA .^ 2));
                    case 'smooth'
                        if ~isfield(params, 'windowSize') || isempty(params.windowSize)
                            error('SignalAnalysis:ChannelOperations:InvalidWindow', ...
                                '窗口大小无效');
                        end
                        winSize = round(params.windowSize);
                        if winSize < 2
                            error('SignalAnalysis:ChannelOperations:InvalidWindow', ...
                                '窗口大小无效');
                        end
                        result = movmean(dataA, winSize);
                end
            else
                error('SignalAnalysis:ChannelOperations:UnknownOp', ...
                    '未知运算类型: %s', op);
            end
        end

        function stats = ComputeStats(signal, refStart, refEnd, sliceStart)
        % ComputeStats 归一化参考窗统计
        %
        % 输入：
        %   signal     - [N×1] 信号
        %   refStart   - 参考窗在切片视图中的起始行
        %   refEnd     - 参考窗在切片视图中的结束行
        %   sliceStart - 通道切片的起始行（映射回原始数据坐标）
        %
        % 输出：
        %   stats - struct：minY/maxY/meanY/stdY

            totalLen = length(signal);
            refStartLocal = max(1, refStart - sliceStart + 1);
            refEndLocal = min(totalLen, refEnd - sliceStart + 1);
            if refStartLocal >= refEndLocal
                refStartLocal = 1;
                refEndLocal = totalLen;
            end
            refSig = signal(refStartLocal:refEndLocal);

            stats = struct();
            stats.minY = min(refSig);
            stats.maxY = max(refSig);
            stats.meanY = mean(refSig);
            stats.stdY = std(refSig);
        end

        function sig = ApplyNorm(sig, normMode, stats)
        % ApplyNorm 按归一化参数变换信号
        %
        % 输入：
        %   sig       - [N×1] 信号
        %   normMode  - 'none'|'minmax'|'zscore'|'meanzero'
        %   stats     - struct(minY, maxY, meanY, stdY)
        %
        % 输出：
        %   sig - 归一化后的信号

            switch lower(normMode)
                case 'none'
                    return;
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

        function [sig, xSig] = SliceAndAlign(data, xRaw, sliceRange, hasXChannel)
        % SliceAndAlign 对信号和横轴数据做切片并对齐
        %
        % 输入：
        %   data        - [N×1] 信号数据
        %   xRaw        - [M×1] 横轴数据（hasXChannel=false 时忽略）
        %   sliceRange  - [start, end] 或 []（不切片）
        %   hasXChannel - 是否有自定义横轴
        %
        % 输出：
        %   sig  - 切片后的信号
        %   xSig - 切片后的横轴（无自定义横轴时为索引 0:N-1）

            if ~isempty(sliceRange)
                sig = ChannelOperations.ApplySlice(data, sliceRange(1), sliceRange(2));
                if hasXChannel
                    xSig = ChannelOperations.ApplySlice(xRaw, sliceRange(1), sliceRange(2));
                    n = min(length(xSig), length(sig));
                    xSig = xSig(1:n);
                    sig = sig(1:n);
                else
                    xSig = (0:length(sig)-1)';
                end
            else
                sig = data;
                if hasXChannel
                    n = min(length(xRaw), length(sig));
                    xSig = xRaw(1:n);
                    sig = sig(1:n);
                else
                    xSig = (0:length(sig)-1)';
                end
            end
        end

        function [activeIdx, snapY] = SnapToNearestChannel(yVals, mouseY, yLimLeft, yLimRight, isRightYMask, axHeightPx)
        % SnapToNearestChannel 像素空间吸附到最近通道
        %
        % 输入：
        %   yVals        - 1×N 各通道 Y 值（NaN 表示无效）
        %   mouseY       - 鼠标 Y 坐标（左Y轴坐标系）
        %   yLimLeft     - 左 Y 轴 [min, max]
        %   yLimRight    - 右 Y 轴 [min, max]
        %   isRightYMask - 1×N logical，true 表示该通道在右 Y 轴
        %   axHeightPx   - axes 像素高度（用于像素距离计算）
        %
        % 输出：
        %   activeIdx - 最近通道索引（无有效通道或超出阈值返回 0）
        %   snapY     - 吸附后的 Y 值（通道原生坐标系）

            SNAP_RADIUS = 30;  % 最大吸附半径（像素）

            validMask = ~isnan(yVals);
            if ~any(validMask)
                activeIdx = 0;
                snapY = NaN;
                return;
            end

            % 计算各轴的 pixels/data-unit
            leftSpan = yLimLeft(2) - yLimLeft(1);
            rightSpan = yLimRight(2) - yLimRight(1);
            pxPerUnitLeft  = axHeightPx / max(leftSpan, eps);
            pxPerUnitRight = axHeightPx / max(rightSpan, eps);

            % 像素距离
            dists = nan(1, length(yVals));
            for vi = find(validMask)
                if isRightYMask(vi)
                    % 右Y通道：mouseY 先从左Y坐标转到右Y坐标
                    mouseNorm = (mouseY - yLimLeft(1)) / max(leftSpan, eps);
                    mouseYRight = mouseNorm * rightSpan + yLimRight(1);
                    dists(vi) = abs(yVals(vi) - mouseYRight) * pxPerUnitRight;
                else
                    dists(vi) = abs(yVals(vi) - mouseY) * pxPerUnitLeft;
                end
            end

            [minDist, nearestK] = min(dists(validMask));
            if minDist > SNAP_RADIUS
                activeIdx = 0;
                snapY = NaN;
                return;
            end
            validIdx = find(validMask);
            activeIdx = validIdx(nearestK);
            snapY = yVals(activeIdx);
        end
    end

    methods (Static, Access = private)
        function sr = RequireSampleRate(params)
        % RequireSampleRate 校验采样率参数
            if ~isfield(params, 'sampleRate') || isempty(params.sampleRate)
                error('SignalAnalysis:ChannelOperations:MissingSampleRate', ...
                    '请先设置采样率');
            end
            sr = params.sampleRate;
        end
    end
end
