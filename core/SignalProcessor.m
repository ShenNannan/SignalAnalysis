classdef SignalProcessor
% SignalProcessor - 信号处理纯函数集合
%
% 无状态，无副作用。所有方法 Static。
% 所有方法的第一个参数都是信号向量，不依赖 Dataset。

    methods (Static)
        function result = ComputeFFT(signal, sampleTime)
        % ComputeFFT 计算单边幅值谱
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleTime - double 采样周期 (s)
        %
        % 输出：
        %   result.Amplitude  [K×1 double] 单边幅值谱
        %   result.Frequency  [K×1 double] 频率轴 Hz
        %   result.Phase      [K×1 double] 相位谱 度
        %   其中 K = floor((N+1)/2)

            validateattributes(signal, {'numeric'}, {'vector'});
            validateattributes(sampleTime, {'numeric'}, {'positive', 'scalar'});

            signal = signal(:);
            N = length(signal);
            Fs = 1 / sampleTime;

            Y = fft(signal);
            K = floor((N+1)/2);

            amplitude = 2 * abs(Y(1:K)) / N;
            amplitude(1) = amplitude(1) / 2;  % DC 分量不乘2

            frequency = (0:K-1)' * Fs / N;

            phase = angle(Y(1:K)) * 180 / pi;

            result = struct();
            result.Amplitude = amplitude;
            result.Frequency = frequency;
            result.Phase = phase;
        end

        function result = ComputePSD(signal, sampleRate)
        % ComputePSD 计算功率谱密度
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleRate - double 采样率 Hz
        %
        % 输出：
        %   result.Power     [P×1 double] 功率谱密度
        %   result.Frequency [P×1 double] 频率轴 Hz

            validateattributes(signal, {'numeric'}, {'vector'});
            validateattributes(sampleRate, {'numeric'}, {'positive', 'scalar'});

            signal = signal(:);
            N = length(signal);

            windowLength = min(256, N);
            noverlap = floor(windowLength / 2);
            nfft = max(256, 2^nextpow2(windowLength));

            [pxx, f] = pwelch(signal, windowLength, noverlap, nfft, sampleRate);

            result = struct();
            result.Power = pxx;
            result.Frequency = f;
        end

        function dy = DifferentiateSignal(signal, sampleTime)
        % DifferentiateSignal 一阶差分近似微分
        %
        % 输入：
        %   signal     - [N×1 double]
        %   sampleTime - double
        %
        % 输出：
        %   dy - [(N-1)×1 double]

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);
            dy = diff(signal) / sampleTime;
        end

        function y = IntegrateSignal(signal, sampleTime)
        % IntegrateSignal 梯形积分
        %
        % 输入：
        %   signal     - [N×1 double]
        %   sampleTime - double
        %
        % 输出：
        %   y - [N×1 double]

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);
            y = cumtrapz(signal) * sampleTime;
        end

        function [movingMean, movingStd] = ComputeMovingStats(signal, windowSize)
        % ComputeMovingStats 滑动均值和标准差
        %
        % 输入：
        %   signal     - [N×1 double]
        %   windowSize - int 窗口大小
        %
        % 输出：
        %   movingMean - [N×1 double]
        %   movingStd  - [N×1 double]

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);
            N = length(signal);

            movingMean = zeros(N, 1);
            movingStd = zeros(N, 1);

            halfWin = floor(windowSize / 2);
            for i = 1:N
                startIdx = max(1, i - halfWin);
                endIdx = min(N, i + halfWin);
                segment = signal(startIdx:endIdx);
                movingMean(i) = mean(segment);
                movingStd(i) = std(segment);
            end
        end

        function filtered = ApplyLowPass(signal, cutoffFreq, damping, sampleTime)
        % ApplyLowPass 二阶低通滤波器
        %
        % 输入：
        %   signal     - [N×1 double]
        %   cutoffFreq - double 截止频率 Hz
        %   damping    - double 阻尼比
        %   sampleTime - double
        %
        % 输出：
        %   filtered - [N×1 double]

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);

            wn = 2 * pi * cutoffFreq;
            dt = sampleTime;

            % 双线性变换
            K = 2 / dt;
            denom = K^2 + 2*damping*wn*K + wn^2;
            b0 = wn^2 / denom;
            b1 = 2 * wn^2 / denom;
            b2 = wn^2 / denom;
            a1 = 2 * (K^2 - wn^2) / denom;
            a2 = (K^2 - 2*damping*wn*K + wn^2) / denom;

            filtered = zeros(size(signal));
            filtered(1) = signal(1);
            if length(signal) > 1
                filtered(2) = signal(2);
            end
            for i = 3:length(signal)
                filtered(i) = b0*signal(i) + b1*signal(i-1) + b2*signal(i-2) ...
                    - a1*filtered(i-1) - a2*filtered(i-2);
            end
        end

        function filtered = ApplyHighPass(signal, cutoffFreq, damping, sampleTime)
        % ApplyHighPass 二阶高通滤波器
        %
        % 输入/输出同 ApplyLowPass

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);

            wn = 2 * pi * cutoffFreq;
            dt = sampleTime;

            K = 2 / dt;
            denom = K^2 + 2*damping*wn*K + wn^2;
            b0 = K^2 / denom;
            b1 = -2 * K^2 / denom;
            b2 = K^2 / denom;
            a1 = 2 * (K^2 - wn^2) / denom;
            a2 = (K^2 - 2*damping*wn*K + wn^2) / denom;

            filtered = zeros(size(signal));
            filtered(1) = signal(1);
            if length(signal) > 1
                filtered(2) = signal(2);
            end
            for i = 3:length(signal)
                filtered(i) = b0*signal(i) + b1*signal(i-1) + b2*signal(i-2) ...
                    - a1*filtered(i-1) - a2*filtered(i-2);
            end
        end

        function filtered = ApplyNotch(signal, zeroFreq, zeroDamp, poleFreq, poleDamp, sampleTime)
        % ApplyNotch 陷波滤波器
        %
        % 输入：
        %   signal    - [N×1 double]
        %   zeroFreq  - double 零点频率 Hz
        %   zeroDamp  - double 零点阻尼
        %   poleFreq  - double 极点频率 Hz
        %   poleDamp  - double 极点阻尼
        %   sampleTime - double
        %
        % 输出：
        %   filtered - [N×1 double]

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);

            wn_z = 2 * pi * zeroFreq;
            wn_p = 2 * pi * poleFreq;
            dt = sampleTime;
            K = 2 / dt;

            % 零点
            num0 = K^2 + 2*zeroDamp*wn_z*K + wn_z^2;
            num1 = 2 * (wn_z^2 - K^2);
            num2 = K^2 - 2*zeroDamp*wn_z*K + wn_z^2;

            % 极点
            den0 = K^2 + 2*poleDamp*wn_p*K + wn_p^2;
            den1 = 2 * (wn_p^2 - K^2);
            den2 = K^2 - 2*poleDamp*wn_p*K + wn_p^2;

            b0 = num0 / den0;
            b1 = num1 / den0;
            b2 = num2 / den0;
            a1 = den1 / den0;
            a2 = den2 / den0;

            filtered = zeros(size(signal));
            filtered(1) = signal(1);
            if length(signal) > 1
                filtered(2) = signal(2);
            end
            for i = 3:length(signal)
                filtered(i) = b0*signal(i) + b1*signal(i-1) + b2*signal(i-2) ...
                    - a1*filtered(i-1) - a2*filtered(i-2);
            end
        end

        function madsd = ComputeMadsd(signal, sampleTime)
        % ComputeMadsd 平均绝对微分（Mean Absolute Signal Derivative）
        %
        % 输入：
        %   signal     - [N×1 double]
        %   sampleTime - double
        %
        % 输出：
        %   madsd - double

            validateattributes(signal, {'numeric'}, {'vector'});
            signal = signal(:);
            dy = diff(signal) / sampleTime;
            madsd = mean(abs(dy));
        end

        function [slope, intercept] = LinearRegression(x, y)
        % LinearRegression 最小二乘线性回归
        %
        % 输入：
        %   x - [N×1 double]
        %   y - [N×1 double]
        %
        % 输出：
        %   slope     - double 斜率
        %   intercept - double 截距

            x = x(:);
            y = y(:);
            n = length(x);
            sx = sum(x);
            sy = sum(y);
            sxx = sum(x.^2);
            sxy = sum(x.*y);

            denom = n * sxx - sx^2;
            slope = (n * sxy - sx * sy) / denom;
            intercept = (sy - slope * sx) / n;
        end
    end
end
