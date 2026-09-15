classdef SignalProcessor
% SignalProcessor - 信号处理纯函数集合
%
% 无状态，无副作用。所有方法 Static。

    methods (Static)
        function [cumRms, f, totalRms] = ComputeCumulativeRMS(signal, sampleRate)
        % ComputeCumulativeRMS 计算累积 RMS 曲线 (手动 Welch PSD，段内去均值)
        %
        % 标准流程：去均值 → 加窗 → 段内去均值 → FFT → 平均 → 累积
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleRate - double 采样率 (Hz)
        %
        % 输出：
        %   cumRms   - [K×1 double] 累积 RMS 曲线 (从 0 开始)
        %   f        - [K×1 double] 频率轴 Hz
        %   totalRms - double 总 RMS 值

            signal = signal(:);
            signal = detrend(signal);
            N = length(signal);
            nfft = min(N, 2^nextpow2(max(64, floor(N/4))));
            try
                [pxx, f] = pwelch(signal, hann(nfft), nfft/2, nfft, sampleRate);
            catch
                [pxx, f] = periodogram(signal, [], [], sampleRate);
            end
            pxx(1) = 0;
            cumRms = sqrt(cumtrapz(f, pxx));
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
            signal = detrend(signal);
            N = length(signal);
            w = hann(N, 'periodic');
            signal = signal .* w;
            signal = signal - mean(signal);
            Y = fft(signal);
            P2 = abs(Y / sum(w));
            P1 = P2(1:floor(N/2)+1);
            P1(2:end-1) = 2 * P1(2:end-1);
            f = sampleRate * (0:floor(N/2)) / N;
        end

        function [f, d] = SkipZeroFreq(freq, data)
        % SkipZeroFreq 跳过零频分量（若存在）
        %
        % 输入：
        %   freq - [K×1] 频率轴
        %   data - [K×1] 对应数据（幅值或累积RMS）
        %
        % 输出：
        %   f - 去掉零频后的频率轴
        %   d - 去掉零频后的数据

            if abs(freq(1)) < eps
                f = freq(2:end);
                d = data(2:end);
            else
                f = freq;
                d = data;
            end
        end
    end
end
