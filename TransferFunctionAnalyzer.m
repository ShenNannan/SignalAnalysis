classdef TransferFunctionAnalyzer < handle
% TransferFunctionAnalyzer - 传函分析 GUI
%
% 替代 TF_analyze.m。programmatic UI。

    properties (SetAccess = private)
        MainFigure              % 主图窗 handle
        Session         SessionData

        % UI 控件（不声明具体类型）
        PathEdit                % uicontrol handle
        InputChannelPopup       % uicontrol handle
        OutputChannelPopup      % uicontrol handle
        BodeMagAxes             % axes handle
        BodePhaseAxes           % axes handle
        NyquistAxes             % axes handle
        GainMarginText          % uicontrol handle
        PhaseMarginText         % uicontrol handle
        BandwidthText           % uicontrol handle

        % 数据
        FreqData        double
        AmpData         double
        PhaseData       double
        InputIdx        double
        OutputIdx       double
    end

    methods
        function obj = TransferFunctionAnalyzer()
        % TransferFunctionAnalyzer 构造函数

            obj.Session = SessionData(1);
            obj.BuildUI();
        end

        function BuildUI(obj)
        % BuildUI 构建界面

            obj.MainFigure = figure( ...
                'Name', 'Signal Analysis - Transfer Function', ...
                'NumberTitle', 'off', ...
                'MenuBar', 'none', ...
                'ToolBar', 'none', ...
                'Position', [150 150 900 700]);

            % 导入区域
            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Data Path:', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.95 0.08 0.03], ...
                'HorizontalAlignment', 'left');

            obj.PathEdit = uicontrol(obj.MainFigure, 'Style', 'edit', ...
                'Units', 'normalized', ...
                'Position', [0.1 0.95 0.7 0.03]);

            uicontrol(obj.MainFigure, 'Style', 'pushbutton', ...
                'String', 'Browse...', ...
                'Units', 'normalized', ...
                'Position', [0.82 0.95 0.08 0.03], ...
                'Callback', @obj.OnBrowse);

            uicontrol(obj.MainFigure, 'Style', 'pushbutton', ...
                'String', 'Import', ...
                'Units', 'normalized', ...
                'Position', [0.91 0.95 0.08 0.03], ...
                'Callback', @obj.OnImport);

            % 通道选择
            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Input:', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.91 0.06 0.03], ...
                'HorizontalAlignment', 'left');

            obj.InputChannelPopup = uicontrol(obj.MainFigure, 'Style', 'popupmenu', ...
                'String', {'-'}, ...
                'Units', 'normalized', ...
                'Position', [0.07 0.91 0.2 0.03]);

            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Output:', ...
                'Units', 'normalized', ...
                'Position', [0.3 0.91 0.06 0.03], ...
                'HorizontalAlignment', 'left');

            obj.OutputChannelPopup = uicontrol(obj.MainFigure, 'Style', 'popupmenu', ...
                'String', {'-'}, ...
                'Units', 'normalized', ...
                'Position', [0.36 0.91 0.2 0.03]);

            % Bode 图
            obj.BodeMagAxes = subplot(2, 2, 1, 'Parent', obj.MainFigure);
            title(obj.BodeMagAxes, 'Bode - Magnitude');
            xlabel(obj.BodeMagAxes, 'Frequency (Hz)');
            ylabel(obj.BodeMagAxes, 'Magnitude (dB)');
            grid(obj.BodeMagAxes, 'on');

            obj.BodePhaseAxes = subplot(2, 2, 3, 'Parent', obj.MainFigure);
            title(obj.BodePhaseAxes, 'Bode - Phase');
            xlabel(obj.BodePhaseAxes, 'Frequency (Hz)');
            ylabel(obj.BodePhaseAxes, 'Phase (deg)');
            grid(obj.BodePhaseAxes, 'on');

            % Nyquist 图
            obj.NyquistAxes = subplot(2, 2, [2 4], 'Parent', obj.MainFigure);
            title(obj.NyquistAxes, 'Nyquist');
            xlabel(obj.NyquistAxes, 'Real');
            ylabel(obj.NyquistAxes, 'Imaginary');
            grid(obj.NyquistAxes, 'on');

            % 分析结果
            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Gain Margin:', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.05 0.12 0.03], ...
                'HorizontalAlignment', 'left');

            obj.GainMarginText = uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', '-', ...
                'Units', 'normalized', ...
                'Position', [0.13 0.05 0.15 0.03], ...
                'HorizontalAlignment', 'left');

            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Phase Margin:', ...
                'Units', 'normalized', ...
                'Position', [0.3 0.05 0.12 0.03], ...
                'HorizontalAlignment', 'left');

            obj.PhaseMarginText = uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', '-', ...
                'Units', 'normalized', ...
                'Position', [0.42 0.05 0.15 0.03], ...
                'HorizontalAlignment', 'left');

            uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', 'Bandwidth:', ...
                'Units', 'normalized', ...
                'Position', [0.6 0.05 0.1 0.03], ...
                'HorizontalAlignment', 'left');

            obj.BandwidthText = uicontrol(obj.MainFigure, 'Style', 'text', ...
                'String', '-', ...
                'Units', 'normalized', ...
                'Position', [0.7 0.05 0.15 0.03], ...
                'HorizontalAlignment', 'left');

            % 操作按钮
            uicontrol(obj.MainFigure, 'Style', 'pushbutton', ...
                'String', 'Compute', ...
                'Units', 'normalized', ...
                'Position', [0.01 0.01 0.15 0.03], ...
                'Callback', @obj.OnCompute);

            uicontrol(obj.MainFigure, 'Style', 'pushbutton', ...
                'String', 'Stability', ...
                'Units', 'normalized', ...
                'Position', [0.18 0.01 0.15 0.03], ...
                'Callback', @obj.OnStability);

            uicontrol(obj.MainFigure, 'Style', 'pushbutton', ...
                'String', 'Export', ...
                'Units', 'normalized', ...
                'Position', [0.35 0.01 0.15 0.03], ...
                'Callback', @obj.OnExport);
        end

        function OnBrowse(obj, ~, ~)
        % OnBrowse 浏览文件

            startPath = pwd;
            [fileName, filePath] = FileExplorer.SelectFile(startPath, ...
                {'*.dat;*.csv;*.txt;*.xlsx;*.mat;*.frfx', 'Data Files (*.dat;*.csv;*.txt;*.xlsx;*.mat;*.frfx)'});

            if ~isempty(filePath)
                set(obj.PathEdit, 'String', filePath);
            end
        end

        function OnImport(obj, ~, ~)
        % OnImport 导入数据

            filePath = get(obj.PathEdit, 'String');
            if isempty(filePath) || ~exist(filePath, 'file')
                errordlg('Please select a valid file', 'Error');
                return;
            end

            [~, ~, ext] = fileparts(filePath);
            ext = lower(ext);

            if strcmp(ext, '.frfx')
                obj.LoadFrfxData(filePath);
            else
                outputDir = fileparts(filePath);
                matPath = DataReaderFactory.ImportToStandard(filePath, outputDir);
                ds = DataReaderFactory.LoadStandard(matPath);
                if obj.Session.HasDataset()
                    obj.Session.RemoveDataset(1);
                end
                [~, fname] = fileparts(filePath);
                obj.Session.AddDataset(ds, fname, matPath);

                nCols = ds.ColumnCount;
                names = cell(1, nCols);
                for i = 1:nCols
                    names{i} = ds.GetColumnName(i);
                end
                set(obj.InputChannelPopup, 'String', names);
                set(obj.OutputChannelPopup, 'String', names);
            end
        end

        function LoadFrfxData(obj, filePath)
        % LoadFrfxData 加载 FRFX 数据

            try
                fid = fopen(filePath, 'r');
                if fid < 0
                    errordlg(['Cannot open: ' filePath], 'Error');
                    return;
                end

                fieldList = {'Measure_Closed_Loop_Data'; ...
                             'Measure_Open_Loop_Data'; ...
                             'Measure_Controller_Data'; ...
                             'Measure_Plant_Data'; ...
                             'Design_Closed_Loop_Data'; ...
                             'Design_Open_Loop_Data'; ...
                             'Design_Controller_Data'; ...
                             'Design_Plant_Data'};

                datasets = {};
                while ~feof(fid)
                    tline = fgetl(fid);
                    if ~ischar(tline), break; end

                    for jj = 1:length(fieldList)
                        if contains(tline, fieldList{jj})
                            fgetl(fid);
                            fgetl(fid);

                            rows = {};
                            while true
                                tline = fgetl(fid);
                                if contains(tline, '];'), break; end
                                parts = textscan(tline, '%s', 'Delimiter', ',', ...
                                    'MultipleDelimsAsOne', 1);
                                rows{end+1} = str2double(parts{1})';
                            end

                            data = vertcat(rows{:});
                            datasets{end+1} = struct('name', fieldList{jj}, 'data', data);
                        end
                    end
                end
                fclose(fid);

                if ~isempty(datasets)
                    names = cellfun(@(d) d.name, datasets, 'UniformOutput', false);
                    set(obj.InputChannelPopup, 'String', names);
                    set(obj.OutputChannelPopup, 'String', names);

                    % 合并所有数据集为一个矩阵
                    data = datasets{1}.data;
                    if length(datasets) > 1
                        for k = 2:length(datasets)
                            minRows = min(size(data,1), size(datasets{k}.data,1));
                            data = data(1:minRows, :);
                            extra = datasets{k}.data(1:minRows, :);
                            if size(extra,1) < size(data,1)
                                extra(end+1:size(data,1), :) = NaN;
                            end
                            data = [data, extra]; %#ok<AGROW>
                        end
                    end
                    ds = Dataset(data, names, [], filePath, 'frfx');
                    if obj.Session.HasDataset()
                        obj.Session.RemoveDataset(1);
                    end
                    obj.Session.AddDataset(ds, 'frfx_data', filePath);
                end
            catch e
                errordlg(e.message, 'Error');
            end
        end

        function OnCompute(obj, ~, ~)
        % OnCompute 计算传函

            if ~obj.Session.HasDataset()
                errordlg('No data loaded', 'Error');
                return;
            end

            ds = obj.Session.GetDataset(1);
            inputIdx = get(obj.InputChannelPopup, 'Value');
            outputIdx = get(obj.OutputChannelPopup, 'Value');

            if inputIdx > ds.ColumnCount || outputIdx > ds.ColumnCount
                errordlg('Invalid channel selection', 'Error');
                return;
            end

            input = ds.GetColumn(inputIdx);
            output = ds.GetColumn(outputIdx);
            sampleTime = ds.SampleTime;

            % 计算 FFT
            fftIn = SignalProcessor.ComputeFFT(input, sampleTime);
            fftOut = SignalProcessor.ComputeFFT(output, sampleTime);

            % 传函 = 输出/输入
            nPts = min(length(fftIn.Frequency), length(fftOut.Frequency));
            obj.FreqData = fftIn.Frequency(1:nPts);
            obj.AmpData = abs(fftOut.Amplitude(1:nPts) ./ fftIn.Amplitude(1:nPts));
            obj.AmpData(isnan(obj.AmpData) | isinf(obj.AmpData)) = 0;
            obj.PhaseData = fftOut.Phase(1:nPts) - fftIn.Phase(1:nPts);
            obj.InputIdx = inputIdx;
            obj.OutputIdx = outputIdx;

            obj.PlotBodeDiagram();
        end

        function PlotBodeDiagram(obj)
        % PlotBodeDiagram 绘制 Bode 图

            % 幅频
            semilogx(obj.BodeMagAxes, obj.FreqData, 20*log10(obj.AmpData), 'b-', 'LineWidth', 1.5);
            title(obj.BodeMagAxes, 'Bode - Magnitude');
            xlabel(obj.BodeMagAxes, 'Frequency (Hz)');
            ylabel(obj.BodeMagAxes, 'Magnitude (dB)');
            grid(obj.BodeMagAxes, 'on');

            % 相频
            semilogx(obj.BodePhaseAxes, obj.FreqData, obj.PhaseData, 'b-', 'LineWidth', 1.5);
            title(obj.BodePhaseAxes, 'Bode - Phase');
            xlabel(obj.BodePhaseAxes, 'Frequency (Hz)');
            ylabel(obj.BodePhaseAxes, 'Phase (deg)');
            grid(obj.BodePhaseAxes, 'on');

            % Nyquist
            realPart = obj.AmpData .* cos(obj.PhaseData * pi / 180);
            imagPart = obj.AmpData .* sin(obj.PhaseData * pi / 180);
            plot(obj.NyquistAxes, realPart, imagPart, 'b-', ...
                realPart, -imagPart, 'b--', 'LineWidth', 0.5);
            hold(obj.NyquistAxes, 'on');
            plot(obj.NyquistAxes, -1, 0, 'r+', 'MarkerSize', 10, 'LineWidth', 2);
            hold(obj.NyquistAxes, 'off');
            title(obj.NyquistAxes, 'Nyquist');
            xlabel(obj.NyquistAxes, 'Real');
            ylabel(obj.NyquistAxes, 'Imaginary');
            grid(obj.NyquistAxes, 'on');
            axis(obj.NyquistAxes, 'equal');
        end

        function OnStability(obj, ~, ~)
        % OnStability 计算稳定裕度

            if isempty(obj.FreqData)
                errordlg('Please compute transfer function first', 'Error');
                return;
            end

            % 增益裕度：幅值=1 时的相位裕度
            ampDb = 20 * log10(obj.AmpData);

            % 找到 0dB 交叉频率
            crossIdx = find(ampDb(1:end-1) > 0 & ampDb(2:end) <= 0, 1, 'first');
            if ~isempty(crossIdx)
                phaseMargin = 180 + obj.PhaseData(crossIdx);
                set(obj.PhaseMarginText, 'String', sprintf('%.1f deg', phaseMargin));
            else
                set(obj.PhaseMarginText, 'String', 'N/A');
            end

            % 找到 -180deg 交叉频率
            phaseData = obj.PhaseData;
            crossIdx = find(phaseData(1:end-1) > -180 & phaseData(2:end) <= -180, 1, 'first');
            if ~isempty(crossIdx)
                gainMargin = -ampDb(crossIdx);
                set(obj.GainMarginText, 'String', sprintf('%.1f dB', gainMargin));
            else
                set(obj.GainMarginText, 'String', 'N/A');
            end

            % 带宽：幅值下降到 -3dB 的频率
            peakAmp = max(ampDb);
            bwIdx = find(ampDb < peakAmp - 3, 1, 'first');
            if ~isempty(bwIdx)
                set(obj.BandwidthText, 'String', sprintf('%.1f Hz', obj.FreqData(bwIdx)));
            else
                set(obj.BandwidthText, 'String', 'N/A');
            end
        end

        function OnExport(obj, ~, ~)
        % OnExport 导出

            fig = figure();
            subplot(2, 1, 1);
            semilogx(obj.FreqData, 20*log10(obj.AmpData), 'b-', 'LineWidth', 1.5);
            title('Bode - Magnitude');
            xlabel('Frequency (Hz)');
            ylabel('Magnitude (dB)');
            grid on;

            subplot(2, 1, 2);
            semilogx(obj.FreqData, obj.PhaseData, 'b-', 'LineWidth', 1.5);
            title('Bode - Phase');
            xlabel('Frequency (Hz)');
            ylabel('Phase (deg)');
            grid on;
        end
    end
end
