classdef SignalProcessor
% SignalProcessor - 信号处理纯函数集合
%
% 无状态，无副作用。所有方法 Static。

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
            amplitude(1) = amplitude(1) / 2;

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

        function [cumRms, f, totalRms] = ComputeCumulativeRMS(signal, sampleRate)
        % ComputeCumulativeRMS 计算累积 RMS 曲线 (基于 pwelch PSD)
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleRate - double 采样率 (Hz)
        %
        % 输出：
        %   cumRms   - [K×1 double] 累积 RMS 曲线
        %   f        - [K×1 double] 频率轴 Hz
        %   totalRms - double 总 RMS 值

            signal = signal(:);
            N = length(signal);
            nfft = min(N, 2^nextpow2(max(64, floor(N/4))));
            try
                [pxx, f] = pwelch(signal, hann(nfft), nfft/2, nfft, sampleRate);
            catch
                [pxx, f] = periodogram(signal, [], [], sampleRate);
            end
            df = f(2) - f(1);
            cumRms = sqrt(cumsum(pxx) * df);
            totalRms = cumRms(end);
        end

        function [P1, f] = ComputeFFTSingleSided(signal, sampleRate)
        % ComputeFFTSingleSided 计算单边 FFT 幅值谱 (线性单位, 去均值, Hann 窗)
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleRate - double 采样率 (Hz)
        %
        % 输出：
        %   P1 - [K×1 double] 单边幅值谱 (线性单位)
        %   f  - [K×1 double] 频率轴 Hz

            signal = signal(:);
            N = length(signal);
            w = hann(N, 'periodic');
            Y = fft((signal - mean(signal)) .* w);
            P2 = abs(Y / sum(w));
            P1 = P2(1:floor(N/2)+1);
            P1(2:end-1) = 2 * P1(2:end-1);
            f = sampleRate * (0:floor(N/2)) / N;
        end
    end
end
