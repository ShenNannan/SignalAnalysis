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
