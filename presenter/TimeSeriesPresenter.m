classdef TimeSeriesPresenter < BasePresenter
% TimeSeriesPresenter - 时域分析控制层
%
% 桥接 TimeSeriesView 与 Model/Service：
%   导入、勾选叠画、切片、归一化、通道运算、重命名、采样率、FFT/PSD 弹窗、
%   导出（figure/Excel）、状态栏。
% 只 addlistener View 事件（句柄集中存 BasePresenter.Listeners）；
% SessionData 事件不被 UI 直接监听。

    properties (SetAccess = private)
        View            % TimeSeriesView
        Session         % SessionData
        StatusCallback  % function handle @(txt)
    end

    methods
        function obj = TimeSeriesPresenter(view, statusCallback)
            obj.View = view;
            obj.Session = SessionData(6);
            if nargin < 2 || isempty(statusCallback)
                statusCallback = @(txt) [];
            end
            obj.StatusCallback = statusCallback;

            obj.TrackListener(addlistener(view, 'BrowseClicked', @obj.OnBrowseFolder));
            obj.TrackListener(addlistener(view, 'ImportButtonClicked', @obj.OnImportFiles));
            obj.TrackListener(addlistener(view, 'ClearAllClicked', @obj.OnClearAll));
            obj.TrackListener(addlistener(view, 'ChannelCheckChanged', @obj.OnChannelCheckChanged));
            obj.TrackListener(addlistener(view, 'AxesRemoveClicked', @obj.OnAxesRemove));
            obj.TrackListener(addlistener(view, 'ExportClicked', @obj.OnExportFigure));
            obj.TrackListener(addlistener(view, 'ExportExcelClicked', @obj.OnExportDatasetExcel));
            obj.TrackListener(addlistener(view, 'ClearPlotClicked', @obj.OnClearPlot));
            obj.TrackListener(addlistener(view, 'FftClicked', @(s, e) obj.ShowSpectrumPopup('fft')));
            obj.TrackListener(addlistener(view, 'PsdClicked', @(s, e) obj.ShowSpectrumPopup('psd')));
            obj.TrackListener(addlistener(view, 'NormClicked', @obj.OnNormalize));
            obj.TrackListener(addlistener(view, 'CalcClicked', @obj.OnCalcChannel));
            obj.TrackListener(addlistener(view, 'RenameChannelClicked', @obj.OnRenameChannel));
            obj.TrackListener(addlistener(view, 'SliceDialogClicked', @obj.OnSliceDialog));
            obj.TrackListener(addlistener(view, 'SliceResetClicked', @obj.OnSliceReset));
            obj.TrackListener(addlistener(view, 'AxesClicked', @obj.OnAxesClicked));
            obj.TrackListener(addlistener(view, 'SetSampleRateClicked', @obj.OnSetSampleRate));
            obj.TrackListener(addlistener(view, 'InlineRenameChannel', @obj.OnInlineRenameChannel));
            obj.TrackListener(addlistener(view, 'InlineRenameDataset', @obj.OnInlineRenameDataset));

            obj.RefreshChannelTable();
        end

        % ---- 导入 ----

        function OnBrowseFolder(obj, ~, ~)
        % OnBrowseFolder 选择文件夹并递归导入
            startPath = obj.Session.GetLastPath(1);
            if isempty(startPath)
                startPath = pwd;
            end
            rootDir = FileExplorer.SelectFolder(startPath);
            if isempty(rootDir)
                return;
            end
            obj.Session.SetLastPath(1, rootDir);

            obj.View.ShowLoading('导入数据...');
            try
                [results, ~] = DataReaderFactory.Import(rootDir);
                obj.View.CloseLoading();
                if isempty(results)
                    obj.View.ShowError('未找到可导入的数据文件');
                    return;
                end
                obj.AddResultsToSession(results);
            catch e
                obj.View.CloseLoading();
                obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
            end
        end

        function OnImportFiles(obj, ~, ~)
        % OnImportFiles 选择文件导入（多通道文件各自独立）
            startPath = obj.Session.GetLastPath(1);
            if isempty(startPath), startPath = pwd; end

            [~, filePaths] = FileExplorer.SelectFiles(startPath, ...
                {'*.dat;*.csv;*.txt;*.xlsx', 'Data Files (*.dat;*.csv;*.txt;*.xlsx)'});
            if isempty(filePaths)
                return;
            end

            obj.View.ShowLoading('导入数据...');
            try
                outputDir = fileparts(filePaths{1});
                fileStructs = cell(1, length(filePaths));
                for k = 1:length(filePaths)
                    [~, fname] = fileparts(filePaths{k});
                    fileStructs{k} = struct('path', filePaths{k}, 'fname', fname);
                end
                results = DataReaderFactory.ProcessFileGroup(fileStructs, outputDir);
                obj.View.CloseLoading();
                obj.Session.SetLastPath(1, outputDir);
                obj.AddResultsToSession(results);
            catch e
                obj.View.CloseLoading();
                obj.View.ShowError(sprintf('导入失败:\n%s', e.message));
            end
        end

        function AddResultsToSession(obj, results)
        % AddResultsToSession 将导入结果加入 Session（跳过已存在的）
            existingPaths = obj.Session.DatasetPaths_;
            added = 0;
            for i = 1:length(results)
                if any(strcmp(results{i}.matPath, existingPaths))
                    continue;
                end
                ds = DataReaderFactory.LoadStandard(results{i}.matPath);
                % 优先使用 .mat 中保存的自定义数据集名
                dsName = obj.LoadDatasetName(results{i}.matPath, results{i}.name);
                obj.Session.AddDataset(ds, dsName, results{i}.matPath);
                added = added + 1;
            end
            obj.RefreshChannelTable();
            obj.StatusCallback(sprintf('  导入 %d 个数据集', added));
        end

        function OnClearAll(obj, ~, ~)
            obj.Session.ClearAllDatasets();
            obj.View.ClearAllAxes();
            obj.RefreshChannelTable();
            obj.StatusCallback(' ');
        end

        % ---- 通道勾选 ----

        function OnChannelCheckChanged(obj, ~, evt)
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();
            if d.colIdx == 0
                ds = obj.Session.GetDataset(d.datasetIdx);
                for c = 1:ds.ColumnCount
                    obj.SetChannelChecked(axIdx, d.datasetIdx, c, d.checked);
                end
            else
                obj.SetChannelChecked(axIdx, d.datasetIdx, d.colIdx, d.checked);
            end
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
        end

        function SetChannelChecked(obj, axIdx, datasetIdx, colIdx, checked)
            if checked
                obj.Session.AddChannelToAxes(axIdx, datasetIdx, colIdx);
            else
                obj.Session.RemoveChannelFromAxes(axIdx, datasetIdx, colIdx);
            end
        end

        % ---- 渲染 ----

        function RenderAxes(obj, axesIdx)
        % RenderAxes 叠画 axes 的全部通道（切片 + 归一化恢复）
            chans = obj.Session.GetAxesChannels(axesIdx);
            if isempty(chans)
                obj.View.ClearAxes(axesIdx);
                return;
            end

            colors = {'b', 'r', 'g', 'c', 'm', 'k'};
            xCell = cell(1, length(chans));
            yCell = cell(1, length(chans));
            labels = cell(1, length(chans));
            colorList = cell(1, length(chans));

            for c = 1:length(chans)
                chan = chans{c};
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sig = ChannelOperations.ApplySlice(chan.Data, chan.SliceRange(1), chan.SliceRange(2));
                else
                    sig = chan.Data;
                end
                sig = obj.ApplyNorm(axesIdx, c, sig);

                xCell{c} = (0:length(sig)-1)';
                yCell{c} = sig;
                labels{c} = chan.Label;
                colorList{c} = colors{mod(c-1, length(colors)) + 1};
            end

            obj.View.RenderWaveform(axesIdx, xCell, yCell, labels, colorList);
        end

        function sig = ApplyNorm(obj, axesIdx, chanIdx, sig)
        % ApplyNorm 按存储的归一化参数变换信号
            normMode = obj.Session.GetAxesNormMode(axesIdx);
            if strcmpi(normMode, 'none')
                return;
            end
            normParams = obj.Session.GetAxesNormParams(axesIdx);
            if ~isfield(normParams, 'channelStats') || isempty(normParams.channelStats)
                return;
            end
            if chanIdx > length(normParams.channelStats)
                return;
            end
            stats = normParams.channelStats{chanIdx};
            switch lower(normMode)
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

        function RefreshChannelTable(obj)
        % RefreshChannelTable 重建通道表（工作集父行 + 通道子行层次结构）
            rows = struct('isParent', {}, 'parentIdx', {}, 'datasetIdx', {}, ...
                'colIdx', {}, 'label', {}, 'datasetName', {}, 'checked', {});
            n = 0;
            for d = 1:obj.Session.DatasetCount
                ds = obj.Session.GetDataset(d);
                dsName = obj.Session.GetDatasetName(d);

                % 父行：工作集
                n = n + 1;
                parentRow = n;
                parentChecked = false;
                r = struct();
                r.isParent = true;
                r.parentIdx = 0;
                r.datasetIdx = d;
                r.colIdx = 0;
                r.label = dsName;
                r.datasetName = dsName;
                r.checked = false;
                rows(n) = r;

                % 子行：通道
                for c = 1:ds.ColumnCount
                    n = n + 1;
                    r = struct();
                    r.isParent = false;
                    r.parentIdx = parentRow;
                    r.datasetIdx = d;
                    r.colIdx = c;
                    r.datasetName = dsName;
                    label = ds.GetColumnName(c);
                    [isChecked, sliceTag] = obj.GetChannelState(d, c);
                    if ~isempty(sliceTag)
                        label = [label sliceTag]; %#ok<AGROW>
                    end
                    r.label = label;
                    r.checked = isChecked;
                    rows(n) = r;
                    if isChecked
                        parentChecked = true;
                    end
                end

                % 更新父行勾选状态
                rows(parentRow).checked = parentChecked;
            end
            obj.View.SetChannelTable(rows);
        end

        function [isChecked, sliceTag] = GetChannelState(obj, datasetIdx, colIdx)
        % GetChannelState 通道在聚焦 axes 上的状态与切片标记
            isChecked = false;
            sliceTag = '';
            chans = obj.Session.GetAxesChannels(obj.View.GetFocusedAxes());
            for sc = 1:length(chans)
                if chans{sc}.DatasetIdx == datasetIdx && chans{sc}.ColIdx == colIdx
                    isChecked = true;
                    if isfield(chans{sc}, 'SliceRange') && ~isempty(chans{sc}.SliceRange)
                        sr = chans{sc}.SliceRange;
                        totalN = length(chans{sc}.Data);
                        segLen = sr(2) - sr(1) + 1;
                        if sr(1) > 1 || sr(2) < totalN || sr(2) > totalN
                            sliceTag = sprintf(' [%d~%d L%d]', sr(1), sr(2), segLen);
                        end
                    end
                    break;
                end
            end
        end

        % ---- axes 增删与清图 ----

        function OnAxesRemove(obj, ~, ~)
            obj.Session.RemoveAxes(obj.View.GetAxesCount() + 1);
        end

        function OnClearPlot(obj, ~, ~)
            obj.View.ClearAllAxes();
            for a = 1:obj.Session.AxesSlotCount
                obj.Session.ClearAxes(a);
            end
            obj.RefreshChannelTable();
        end

        % ---- 归一化 ----

        function OnNormalize(obj, ~, evt)
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();
            obj.Session.SetAxesNormMode(axIdx, d.mode);
            if strcmpi(d.mode, 'none')
                obj.Session.SetAxesNormParams(axIdx, struct());
            else
                obj.Session.SetAxesNormParams(axIdx, obj.ComputeNormParams(axIdx));
            end
            obj.RenderAxes(axIdx);
        end

        function normParams = ComputeNormParams(obj, axIdx)
        % ComputeNormParams 从当前 axes 视图计算归一化参数
            ax = obj.View.GetAxes(axIdx);
            if isempty(ax)
                normParams = struct();
                return;
            end
            xl = xlim(ax);
            refStart = max(1, round(xl(1)));
            refEnd = round(xl(2));

            chans = obj.Session.GetAxesChannels(axIdx);
            if isempty(chans)
                normParams = struct();
                return;
            end

            channelStats = {};
            for i = 1:length(chans)
                chan = chans{i};
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sliceStart = chan.SliceRange(1);
                else
                    sliceStart = 1;
                end
                channelStats{end+1} = ChannelOperations.ComputeStats( ... %#ok<AGROW>
                    chan.Data, refStart, refEnd, sliceStart);
            end

            normParams = struct();
            normParams.refWindow = [refStart, refEnd];
            normParams.channelStats = channelStats;
        end

        % ---- 通道操作（切片/重命名） ----

        function OnSliceDialog(obj, ~, evt)
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();
            chans = obj.Session.GetAxesChannels(axIdx);
            chanIdx = obj.FindChannelIndex(chans, d.datasetIdx, d.colIdx);
            if chanIdx == 0
                obj.View.ShowError('请先勾选该通道到当前 axes');
                return;
            end

            chan = chans{chanIdx};
            totalRows = length(chan.Data);
            currentRange = chan.SliceRange;
            currentLen = currentRange(2) - currentRange(1) + 1;
            ds = obj.Session.GetDataset(d.datasetIdx);
            colName = ds.GetColumnName(d.colIdx);

            answer = inputdlg({'起点行号:', '长度:'}, ...
                sprintf('设置切片范围 - %s (共 %d 行)', colName, totalRows), ...
                1, {num2str(currentRange(1)), num2str(currentLen)});
            if isempty(answer), return; end

            startRow = round(str2double(answer{1}));
            segLen = round(str2double(answer{2}));
            if isnan(startRow) || isnan(segLen) || startRow < 1 || segLen < 1
                obj.View.ShowError('起点 ≥1, 长度 ≥1');
                return;
            end
            endRow = startRow + segLen - 1;
            if endRow > totalRows && segLen > startRow
                obj.View.ShowError(sprintf('回绕时长度不能超过起点 %d', startRow));
                return;
            end

            obj.Session.SetChannelSlice(axIdx, chanIdx, startRow, endRow);
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
        end

        function OnSliceReset(obj, ~, evt)
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();
            chans = obj.Session.GetAxesChannels(axIdx);
            chanIdx = obj.FindChannelIndex(chans, d.datasetIdx, d.colIdx);
            if chanIdx == 0, return; end

            obj.Session.SetChannelSlice(axIdx, chanIdx, 1, length(chans{chanIdx}.Data));
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
        end

        function chanIdx = FindChannelIndex(~, chans, datasetIdx, colIdx)
        % FindChannelIndex 在通道列表中查找 datasetIdx/colIdx
            chanIdx = 0;
            for c = 1:length(chans)
                if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                    chanIdx = c;
                    return;
                end
            end
        end

        function OnRenameChannel(obj, ~, evt)
            d = evt.Data;
            ds = obj.Session.GetDataset(d.datasetIdx);
            currentName = ds.GetColumnName(d.colIdx);
            answer = inputdlg('新列名:', '重命名通道', 1, {currentName});
            if isempty(answer), return; end

            newName = strtrim(answer{1});
            if isempty(newName) || strcmp(newName, currentName)
                return;
            end

            newNames = ds.ColumnNames;
            newNames{d.colIdx} = newName;
            newDs = ds.RebuildWithColumnNames(newNames);
            obj.Session.UpdateDataset(d.datasetIdx, newDs);

            matPath = obj.Session.GetDatasetMatPath(d.datasetIdx);
            if ~isempty(matPath)
                sa_column_names = newNames; %#ok<NASGU>
                save(matPath, 'sa_column_names', '-append');
                DataReaderFactory.UpdateColumnNamesInMeta(matPath, newNames);
            end

            obj.RefreshChannelTable();
            obj.RenderAxes(obj.View.GetFocusedAxes());
        end

        function OnInlineRenameChannel(obj, ~, evt)
        % OnInlineRenameChannel 表格内联重命名通道（无弹窗）
            d = evt.Data;
            ds = obj.Session.GetDataset(d.datasetIdx);
            currentName = ds.GetColumnName(d.colIdx);
            newName = strtrim(d.newName);
            if isempty(newName) || strcmp(newName, currentName)
                return;
            end
            newNames = ds.ColumnNames;
            newNames{d.colIdx} = newName;
            newDs = ds.RebuildWithColumnNames(newNames);
            obj.Session.UpdateDataset(d.datasetIdx, newDs);

            matPath = obj.Session.GetDatasetMatPath(d.datasetIdx);
            if ~isempty(matPath)
                sa_column_names = newNames; %#ok<NASGU>
                save(matPath, 'sa_column_names', '-append');
                DataReaderFactory.UpdateColumnNamesInMeta(matPath, newNames);
            end

            obj.RefreshChannelTable();
            obj.RenderAxes(obj.View.GetFocusedAxes());
        end

        function OnInlineRenameDataset(obj, ~, evt)
        % OnInlineRenameDataset 表格内联重命名数据集（无弹窗）
            d = evt.Data;
            currentName = obj.Session.GetDatasetName(d.datasetIdx);
            newName = strtrim(d.newName);
            if isempty(newName) || strcmp(newName, currentName)
                return;
            end
            obj.Session.SetDatasetName(d.datasetIdx, newName);

            matPath = obj.Session.GetDatasetMatPath(d.datasetIdx);
            if ~isempty(matPath)
                sa_dataset_name = newName; %#ok<NASGU>
                save(matPath, 'sa_dataset_name', '-append');
            end

            obj.RefreshChannelTable();
            obj.RenderAxes(obj.View.GetFocusedAxes());
        end

        function name = LoadDatasetName(~, matPath, fallback)
        % LoadDatasetName 从 .mat 读取 sa_dataset_name，无则返回 fallback
            name = fallback;
            try
                S = load(matPath, 'sa_dataset_name');
                if isfield(S, 'sa_dataset_name') && ~isempty(S.sa_dataset_name)
                    name = regexprep(strtrim(S.sa_dataset_name), '^[▼▶]\s*', '');
                end
            catch
            end
        end

        function sampleRate = EnsureSampleRate(obj, datasetIdx)
        % EnsureSampleRate 采样率为空时弹窗设置并回写磁盘；取消返回 []
            ds = obj.Session.GetDataset(datasetIdx);
            sampleRate = ds.SampleRate;
            if ~isempty(sampleRate)
                return;
            end
            dsName = obj.Session.GetDatasetName(datasetIdx);
            answer = inputdlg(sprintf('数据集: %s\n采样率 (Hz):', dsName), ...
                '设置采样率', 1, {''});
            if isempty(answer), return; end
            newRate = str2double(answer{1});
            if isnan(newRate) || newRate <= 0
                obj.View.ShowError('采样率必须为正数');
                return;
            end
            obj.Session.UpdateSampleRate(datasetIdx, newRate);
            matPath = obj.Session.GetDatasetPath(datasetIdx);
            if ~isempty(matPath) && exist(matPath, 'file')
                DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
                jsonPath = strrep(matPath, '_standardized.mat', '_standardized_meta.json');
                if exist(jsonPath, 'file')
                    try
                        meta = jsondecode(fileread(jsonPath));
                        meta.sample_rate = newRate;
                        DataReaderFactory.WriteJson(jsonPath, meta);
                    catch
                    end
                end
            end
            sampleRate = newRate;
        end

        function OnSetSampleRate(obj, ~, evt)
        % OnSetSampleRate 右键设置采样频率（单数据集）
            d = evt.Data;
            ds = obj.Session.GetDataset(d.datasetIdx);
            currentRate = ds.SampleRate;
            dsName = obj.Session.GetDatasetName(d.datasetIdx);
            default = '';
            if ~isempty(currentRate), default = num2str(currentRate); end
            answer = inputdlg(sprintf('数据集: %s\n采样率 (Hz):', dsName), ...
                '设置采样率', 1, {default});
            if isempty(answer), return; end
            newRate = str2double(answer{1});
            if isnan(newRate) || newRate <= 0
                obj.View.ShowError('采样率必须为正数');
                return;
            end
            obj.Session.UpdateSampleRate(d.datasetIdx, newRate);
            matPath = obj.Session.GetDatasetPath(d.datasetIdx);
            if ~isempty(matPath) && exist(matPath, 'file')
                DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
                jsonPath = strrep(matPath, '_standardized.mat', '_standardized_meta.json');
                if exist(jsonPath, 'file')
                    try
                        meta = jsondecode(fileread(jsonPath));
                        meta.sample_rate = newRate;
                        DataReaderFactory.WriteJson(jsonPath, meta);
                    catch
                    end
                end
            end
            obj.RefreshChannelTable();
            obj.RenderAxes(obj.View.GetFocusedAxes());
            obj.StatusCallback(sprintf('  %s 采样率 = %g Hz', dsName, newRate));
        end

        % ---- FFT/PSD 弹窗 ----

        function ShowSpectrumPopup(obj, analysisType)
        % ShowSpectrumPopup uifigure 弹窗：原始信号 + FFT/PSD
            axIdx = obj.View.GetFocusedAxes();
            chans = obj.Session.GetAxesChannels(axIdx);
            if isempty(chans)
                obj.View.ShowError('请先勾选通道到当前 axes');
                return;
            end

            colors = {'b', 'r', 'g', 'c', 'm', 'k'};
            fig = uifigure('Name', sprintf('Spectrum - %s', upper(analysisType)), ...
                'NumberTitle', 'off', 'Position', [200 150 900 700]);
            obj.TrackPopup(fig);
            fig.CloseRequestFcn = @(s, e) obj.RemovePopup(fig);

            g = uigridlayout(fig, [2 1], 'RowHeight', {'1x', '1x'}, ...
                'Padding', [6 6 6 6], 'RowSpacing', 4);
            ax1 = uiaxes(g);
            ax1.Layout.Row = 1;
            ax2 = uiaxes(g);
            ax2.Layout.Row = 2;
            hold(ax1, 'on');
            hold(ax2, 'on');

            nPlotted = 0;
            for c = 1:length(chans)
                chan = chans{c};

                sampleRate = obj.EnsureSampleRate(chan.DatasetIdx);
                if isempty(sampleRate) || isnan(sampleRate) || sampleRate <= 0
                    continue;
                end

                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sig = ChannelOperations.ApplySlice(chan.Data, chan.SliceRange(1), chan.SliceRange(2));
                else
                    sig = chan.Data;
                end

                sampleIdx = (0:length(sig)-1)';
                chanColor = colors{mod(c-1, length(colors)) + 1};
                chanLabel = chan.Label;
                nPlotted = nPlotted + 1;

                plot(ax1, sampleIdx, sig, 'Color', chanColor, 'DisplayName', chanLabel);

                switch lower(analysisType)
                    case 'fft'
                        [P1, freq] = SignalProcessor.ComputeFFTSingleSided(sig, sampleRate);
                        if freq(1) == 0
                            semilogx(ax2, freq(2:end), P1(2:end), 'Color', chanColor, 'DisplayName', chanLabel);
                        else
                            semilogx(ax2, freq, P1, 'Color', chanColor, 'DisplayName', chanLabel);
                        end
                    case 'psd'
                        [cumRms, freq, totalRms] = SignalProcessor.ComputeCumulativeRMS(sig, sampleRate);
                        label = sprintf('%s (RMS=%.4f)', chanLabel, totalRms);
                        if freq(1) == 0
                            semilogx(ax2, freq(2:end), cumRms(2:end), 'Color', chanColor, 'DisplayName', label);
                        else
                            semilogx(ax2, freq, cumRms, 'Color', chanColor, 'DisplayName', label);
                        end
                end
            end

            hold(ax1, 'off');
            hold(ax2, 'off');
            xlabel(ax1, 'Sample Index');
            ylabel(ax1, 'Amplitude');
            title(ax1, 'Time Domain Signal');
            grid(ax1, 'on');
            xlabel(ax2, 'Frequency (Hz)');
            grid(ax2, 'on');
            if strcmpi(analysisType, 'fft')
                ylabel(ax2, 'Amplitude');
                title(ax2, 'FFT Single-Sided Amplitude Spectrum');
            else
                ylabel(ax2, 'Cumulative RMS');
                title(ax2, 'Cumulative RMS (from PSD)');
            end
            if nPlotted > 1
                legend(ax1, 'Interpreter', 'none', 'Location', 'northwest');
                legend(ax2, 'Interpreter', 'none', 'Location', 'northwest');
            end
        end

        function RemovePopup(obj, fig)
        % RemovePopup 弹窗自行关闭：仅从集合移除
            for i = 1:numel(obj.PopupFigures)
                if isequal(obj.PopupFigures{i}, fig)
                    obj.PopupFigures(i) = [];
                    break;
                end
            end
            delete(fig);
        end

        % ---- 通道运算对话框 ----

        function OnCalcChannel(obj, ~, ~)
            if obj.Session.DatasetCount == 0
                obj.View.ShowError('请先导入数据');
                return;
            end

            [channelList, channelMap] = obj.BuildChannelList();
            if isempty(channelList)
                obj.View.ShowError('无可用通道');
                return;
            end

            opTypes = {'A + B', 'A - B', 'A × B', 'A ÷ B', ...
                       'diff(A)', 'cumsum(A)', '|A|', 'A²', '√A', ...
                       'log₁₀(A)', 'detrend(A)', 'RMS(A)', 'smooth(A)'};
            opKeys  = {'add', 'sub', 'mul', 'div', ...
                       'diff', 'cumsum', 'abs', 'square', 'sqrt', ...
                       'log10', 'detrend', 'rms', 'smooth'};

            dlg = uifigure('Name', '通道运算', 'NumberTitle', 'off', ...
                'Position', [400 260 380 480], 'Resize', 'off');
            obj.TrackPopup(dlg);
            dlg.CloseRequestFcn = @(s, e) obj.RemovePopup(dlg);

            g = uigridlayout(dlg, [10 2], ...
                'RowHeight', repmat({32}, 1, 10), ...
                'ColumnWidth', {110, '1x'}, ...
                'Padding', [10 10 10 10], 'RowSpacing', 6);

            uilabel(g, 'Text', '运算类型:');
            opPopup = uidropdown(g, 'Items', opTypes, 'Value', opTypes{1}, ...
                'ValueChangedFcn', @(s, e) updateOpType());
            uilabel(g, 'Text', '通道A:');
            popupA = uidropdown(g, 'Items', channelList, 'Value', channelList{1}, ...
                'ValueChangedFcn', @(s, e) updateOpType());
            uilabel(g, 'Text', '通道B:');
            popupB = uidropdown(g, 'Items', channelList, 'Value', channelList{1}, ...
                'Enable', 'off');
            uilabel(g, 'Text', 'A 起点:');
            editA1 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf]);
            uilabel(g, 'Text', 'A 长度:');
            editA2 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf]);
            uilabel(g, 'Text', 'B 起点:');
            editB1 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf], 'Enable', 'off');
            uilabel(g, 'Text', 'B 长度:');
            editB2 = uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 inf], 'Enable', 'off');
            winLabel = uilabel(g, 'Text', '窗口大小:');
            winLabel.Visible = 'off';
            editWin = uieditfield(g, 'numeric', 'Value', 10, 'Limits', [2 inf]);
            editWin.Visible = 'off';
            uilabel(g, 'Text', '结果名称:');
            editName = uieditfield(g, 'text', 'Value', '');
            btnGrid = uigridlayout(g, [1 2], 'ColumnWidth', {'1x', '1x'}, ...
                'ColumnSpacing', 8);
            btnGrid.Layout.Column = [1 2];
            uibutton(btnGrid, 'push', 'Text', '确定', 'ButtonPushedFcn', @(s, e) doCalc());
            uibutton(btnGrid, 'push', 'Text', '取消', 'ButtonPushedFcn', @(s, e) obj.RemovePopup(dlg));

            updateOpType();

            function updateOpType()
                val = find(strcmp(opPopup.Value, opTypes), 1);
                if isempty(val), val = 1; end
                key = opKeys{val};
                isDual = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));
                isSmooth = strcmp(key, 'smooth');

                if isDual
                    popupB.Enable = 'on';
                    editB1.Enable = 'on';
                    editB2.Enable = 'on';
                else
                    popupB.Enable = 'off';
                    editB1.Enable = 'off';
                    editB2.Enable = 'off';
                end

                if isSmooth
                    winLabel.Visible = 'on';
                    editWin.Visible = 'on';
                else
                    winLabel.Visible = 'off';
                    editWin.Visible = 'off';
                end

                idxA = find(strcmp(popupA.Value, channelList), 1);
                if isempty(idxA), idxA = 1; end
                nameA = strrep(channelList{idxA}, ' > ', '_');
                if isDual
                    idxB = find(strcmp(popupB.Value, channelList), 1);
                    if isempty(idxB), idxB = 1; end
                    nameB = strrep(channelList{idxB}, ' > ', '_');
                    ops = {'+', '-', '×', '÷'};
                    defaultName = sprintf('%s%s%s', nameA, ops{val}, nameB);
                else
                    opNames = {'diff', 'cumsum', 'abs', 'sq', 'sqrt', 'log10', 'detrend', 'rms', 'smooth'};
                    defaultName = sprintf('%s(%s)', opNames{val - 4}, nameA);
                end
                if length(defaultName) > 63
                    defaultName = defaultName(1:63);
                end
                editName.Value = defaultName;

                if idxA <= size(channelMap, 1)
                    dsA = obj.Session.GetDataset(channelMap(idxA, 1));
                    editA2.Value = max(1, dsA.RowCount);
                end
                if isDual && idxB <= size(channelMap, 1)
                    dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                    editB2.Value = max(1, dsB.RowCount);
                end
            end

            function doCalc()
                try
                    val = find(strcmp(opPopup.Value, opTypes), 1);
                    if isempty(val), val = 1; end
                    key = opKeys{val};
                    isDual = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));

                    idxA = find(strcmp(popupA.Value, channelList), 1);
                    if isempty(idxA), idxA = 1; end
                    dsIdxA = channelMap(idxA, 1);
                    colIdxA = channelMap(idxA, 2);
                    dsA = obj.Session.GetDataset(dsIdxA);
                    dataA = dsA.GetColumn(colIdxA);

                    a1 = round(editA1.Value);
                    aLen = round(editA2.Value);
                    a1 = max(1, a1);
                    aLen = max(1, min(aLen, size(dataA, 1) - a1 + 1));
                    dataA = dataA(a1 : a1 + aLen - 1);

                    params = struct();
                    if isDual
                        idxB = find(strcmp(popupB.Value, channelList), 1);
                        if isempty(idxB), idxB = 1; end
                        dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                        dataB = dsB.GetColumn(channelMap(idxB, 2));
                        b1 = round(editB1.Value);
                        bLen = round(editB2.Value);
                        b1 = max(1, b1);
                        bLen = max(1, min(bLen, size(dataB, 1) - b1 + 1));
                        dataB = dataB(b1 : b1 + bLen - 1);

                        if length(dataA) ~= length(dataB)
                            obj.View.ShowError(sprintf('窗口长度不一致: A=%d, B=%d', ...
                                length(dataA), length(dataB)));
                            return;
                        end
                    else
                        dataB = [];
                        switch key
                            case 'diff'
                                params.sampleRate = obj.RequireSampleRateForCalc(dsIdxA);
                            case 'cumsum'
                                params.sampleRate = obj.RequireSampleRateForCalc(dsIdxA);
                            case 'smooth'
                                params.windowSize = round(editWin.Value);
                        end
                    end

                    if strcmp(key, 'rms')
                        rmsVal = ChannelOperations.Compute('rms', dataA, [], params);
                        uialert(dlg, sprintf('RMS = %.6g', rmsVal), 'RMS', 'Icon', 'info');
                        obj.RemovePopup(dlg);
                        return;
                    end

                    result = ChannelOperations.Compute(key, dataA, dataB, params);

                    resultName = strtrim(editName.Value);
                    if isempty(resultName)
                        resultName = sprintf('calc_%d', obj.Session.DatasetCount + 1);
                    end

                    tempDir = tempname;
                    mkdir(tempDir);
                    matPath = DataReaderFactory.SaveStandard( ...
                        result, {resultName}, tempDir, resultName, 'calc', 'calc');
                    newDs = DataReaderFactory.LoadStandard(matPath);
                    obj.Session.AddDataset(newDs, resultName, matPath);
                    obj.RefreshChannelTable();

                    obj.RemovePopup(dlg);
                    fprintf('[Calc] %s → 新数据集 (%d×%d)\n', resultName, size(result, 1), size(result, 2));
                catch e
                    obj.View.ShowError(sprintf('运算失败:\n%s', e.message));
                end
            end
        end

        function sr = RequireSampleRateForCalc(obj, datasetIdx)
        % RequireSampleRateForCalc diff/cumsum 前确保采样率已设置
            sr = obj.EnsureSampleRate(datasetIdx);
            if isempty(sr) || isnan(sr) || sr <= 0
                error('SignalAnalysis:TimeSeriesPresenter:MissingSampleRate', ...
                    '请先设置采样率');
            end
        end

        function [channelList, channelMap] = BuildChannelList(obj)
            channelList = {};
            channelMap = zeros(0, 2);
            for d = 1:obj.Session.DatasetCount
                ds = obj.Session.GetDataset(d);
                dsName = obj.Session.GetDatasetName(d);
                for c = 1:ds.ColumnCount
                    channelList{end+1} = sprintf('%s > %s', dsName, ds.GetColumnName(c)); %#ok<AGROW>
                    channelMap(end+1, :) = [d, c]; %#ok<AGROW>
                end
            end
        end

        % ---- 导出 ----

        function OnExportFigure(obj, ~, ~)
        % OnExportFigure 导出全部 axes 到独立 legacy figure（视觉属性保真）
            n = obj.View.GetAxesCount();
            if n == 0
                return;
            end
            fig = figure('Name', 'Export', 'NumberTitle', 'off');
            obj.TrackPopup(fig);

            for i = 1:n
                ax = obj.View.GetAxes(i);
                sub = subplot(n, 1, i, 'Parent', fig);
                lines = flipud(findobj(ax, 'Type', 'line'));
                hold(sub, 'on');
                for k = 1:numel(lines)
                    l = lines(k);
                    plot(sub, l.XData, l.YData, ...
                        'Color', l.Color, ...
                        'LineStyle', l.LineStyle, ...
                        'LineWidth', l.LineWidth, ...
                        'Marker', l.Marker, ...
                        'MarkerSize', l.MarkerSize, ...
                        'DisplayName', l.DisplayName);
                end
                hold(sub, 'off');
                grid(sub, 'on');
                title(sub, get(get(ax, 'Title'), 'String'));
                ylabel(sub, get(get(ax, 'YLabel'), 'String'));
                if i == n
                    xlabel(sub, 'Sample Index');
                end
                if numel(lines) > 1
                    legend(sub, 'Location', 'best', 'Interpreter', 'none');
                end
            end
        end

        function OnExportDatasetExcel(obj, ~, evt)
        % OnExportDatasetExcel 手动导出数据集为 Excel（_review.xlsx）
            d = evt.Data;
            matPath = obj.Session.GetDatasetMatPath(d.datasetIdx);
            if isempty(matPath) || ~exist(matPath, 'file')
                obj.View.ShowError('数据集无对应 .mat 文件，无法导出');
                return;
            end

            dsName = obj.Session.GetDatasetName(d.datasetIdx);
            [dirPart, ~, ~] = fileparts(matPath);
            xlsxPath = fullfile(dirPart, [dsName '_review.xlsx']);
            obj.View.ShowLoading('导出 Excel...');
            try
                DataReaderFactory.ExportToExcel(matPath, xlsxPath);
                obj.View.CloseLoading();
                obj.View.ShowInfo(sprintf('已导出:\n%s', xlsxPath));
            catch e
                obj.View.CloseLoading();
                obj.View.ShowError(sprintf('导出失败:\n%s', e.message));
            end
        end

        % ---- 状态栏 ----

        function OnAxesClicked(obj, ~, evt)
        % OnAxesClicked 点击 axes：更新状态栏坐标
            d = evt.Data;
            if d.axesIdx > 0
                obj.StatusCallback(sprintf('  Axes %d  |  X = %.6g  |  Y = %.6g', ...
                    d.axesIdx, d.x, d.y));
            else
                obj.StatusCallback(' ');
            end
            obj.RefreshChannelTable();
        end

    end
end
