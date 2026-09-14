classdef SignalProcessor
% SignalProcessor - 信号处理纯函数集合
%
% 无状态，无副作用。所有方法 Static。

    methods (Static)
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

        function [rmsAmp, f, totalRms] = ComputeRMSSpectrum(signal, sampleRate)
        % ComputeRMSSpectrum 每频率 bin 的 RMS 幅值谱
        %
        % 基于 Welch PSD，sqrt(psd * df) 得到每 bin 的 RMS 贡献
        % 非累积，可直接看到各频率的 RMS 大小
        %
        % 输出：
        %   rmsAmp   - [K×1 double] 每 bin RMS 幅值 (线性单位)
        %   f        - [K×1 double] 频率轴 Hz
        %   totalRms - double 总 RMS = sqrt(sum(rmsAmp.^2))

            signal = signal(:);
            N = length(signal);
            nfft = min(N, 2^nextpow2(max(256, floor(N/4))));
            win = hann(nfft, 'periodic');
            noverlap = round(nfft * 0.5);
            try
                [pxx, f] = pwelch(signal, win, noverlap, nfft, sampleRate);
            catch
                [pxx, f] = periodogram(signal, [], [], sampleRate);
            end
            df = f(2) - f(1);
            rmsAmp = sqrt(pxx .* df);
            rmsAmp = rmsAmp(:);
            f = f(:);
            totalRms = sqrt(sum(rmsAmp.^2));
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
        function [psd, f] = ComputePSDWelch(signal, sampleRate, nfft)
        % ComputePSDWelch Welch 平均周期图法 PSD 估计
        %
        % 分段加窗 → FFT → 平均，消除噪声毛刺
        %
        % 输入：
        %   signal     - [N×1 double] 时域信号
        %   sampleRate - double 采样率 (Hz)
        %   nfft       - (可选) FFT 点数，默认自动选择
        %
        % 输出：
        %   psd - [K×1 double] 功率谱密度 (单位²/Hz)
        %   f   - [K×1 double] 频率轴 Hz

            signal = signal(:);
            N = length(signal);
            if nargin < 3 || isempty(nfft)
                nfft = min(N, 2^nextpow2(max(256, floor(N/4))));
            end
            win = hann(nfft, 'periodic');
            noverlap = round(nfft * 0.5);
            try
                [psd, f] = pwelch(signal, win, noverlap, nfft, sampleRate);
            catch
                [psd, f] = periodogram(signal, [], [], sampleRate);
            end
            psd = psd(:);
            f = f(:);
        end

        function [amp, f] = ComputeSpectrumWelch(signal, sampleRate, nfft)
        % ComputeSpectrumWelch Welch 平均周期图法 → 单边幅值谱 (线性单位)
        %
        % 与 ComputeFFTSingleSided 输出格式一致，但更平滑

            signal = signal(:);
            N = length(signal);
            if nargin < 3 || isempty(nfft)
                nfft = min(N, 2^nextpow2(max(256, floor(N/4))));
            end
            win = hann(nfft, 'periodic');
            noverlap = round(nfft * 0.5);
            try
                [psd, f] = pwelch(signal, win, noverlap, nfft, sampleRate);
            catch
                [psd, f] = periodogram(signal, [], [], sampleRate);
            end
            df = f(2) - f(1);
            amp = sqrt(psd .* df);
            amp = amp(:); f = f(:);
        end
    end
end
