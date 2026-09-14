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
        LastFocusedAxes_ = 0  % 上次聚焦的 axes 索引（避免重复刷新通道表）
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
            obj.TrackListener(addlistener(view, 'SetXAxisClicked', @obj.OnSetXAxis));
            obj.TrackListener(addlistener(view, 'ClearXAxisClicked', @obj.OnClearXAxis));
            obj.TrackListener(addlistener(view, 'SetRightYAxisClicked', @obj.OnSetRightYAxis));
            obj.TrackListener(addlistener(view, 'ClearRightYAxisClicked', @obj.OnClearRightYAxis));

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
                {'*.dat;*.csv;*.txt;*.xlsx;*.mat', 'Data Files (*.dat;*.csv;*.txt;*.xlsx;*.mat)'});
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
                dsName = DataReaderFactory.LoadDatasetName(results{i}.matPath);
                if isempty(dsName), dsName = results{i}.name; end
                obj.Session.AddDataset(ds, dsName, results{i}.matPath);
                added = added + 1;
            end
            obj.RefreshChannelTable();
            obj.StatusCallback(sprintf('  导入 %d 个数据集', added));
        end

        function OnClearAll(obj, ~, ~)
            obj.Session.ClearAllDatasets();
            obj.View.ClearAllAxes();
            obj.SyncViewAxisState(obj.View.GetFocusedAxes());
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
            obj.SyncViewAxisState(axIdx);
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
        % RenderAxes 叠画 axes 的全部通道（切片 + 归一化 + 自定义横轴 + 双Y轴）
            chans = obj.Session.GetAxesChannels(axesIdx);
            if isempty(chans)
                obj.View.ClearAxes(axesIdx);
                return;
            end

            % ---- 横轴数据 ----
            [xDsIdx, xColIdx] = obj.Session.GetXChannel(axesIdx);
            hasXChannel = ~isempty(xDsIdx);
            if hasXChannel
                xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
            else
                xRaw = [];
            end

            % ---- 右Y通道识别（支持多个）----
            rightYRefs = obj.Session.GetRightYChannel(axesIdx);
            hasRightY = ~isempty(rightYRefs);

            colors = {'b', 'r', 'g', 'c', 'm', 'k'};
            xCell = {};
            yCell = {};
            labels = {};
            colorList = {};
            leftIdx = 0;

            % 构建右Y通道快速查找表
            rightYSet = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            if hasRightY
                for ri = 1:length(rightYRefs)
                    key = sprintf('%d_%d', rightYRefs{ri}.DatasetIdx, rightYRefs{ri}.ColIdx);
                    rightYSet(key) = true;
                end
            end

            for c = 1:length(chans)
                chan = chans{c};

                % 右Y通道单独处理
                chanKey = sprintf('%d_%d', chan.DatasetIdx, chan.ColIdx);
                if hasRightY && rightYSet.isKey(chanKey)
                    continue;
                end
                % X轴通道不画Y
                if hasXChannel && chan.DatasetIdx == xDsIdx && chan.ColIdx == xColIdx
                    continue;
                end

                [sig, xSig] = obj.SliceChannel(chan, xRaw, hasXChannel);
                sig = obj.ApplyNorm(axesIdx, c, sig);

                leftIdx = leftIdx + 1;
                xCell{leftIdx} = xSig;
                yCell{leftIdx} = sig;
                labels{leftIdx} = chan.Label;
                colorList{leftIdx} = colors{obj.ChannelColorIndex(chan.DatasetIdx, chan.ColIdx, length(colors))};
            end

            % ---- 右Y通道数据（多个）----
            rightYData = struct('x', {{}}, 'y', {{}}, 'labels', {{}}, 'colors', {{}});
            if hasRightY
                rx = {}; ry = {}; rl = {}; rc = {};
                for ri = 1:length(rightYRefs)
                    ref = rightYRefs{ri};
                    rightYChan = obj.FindChannelInList(chans, ref.DatasetIdx, ref.ColIdx);
                    if ~isempty(rightYChan)
                        [rySig, ryX] = obj.SliceChannel(rightYChan, xRaw, hasXChannel);
                        rightColor = colors{obj.ChannelColorIndex(rightYChan.DatasetIdx, rightYChan.ColIdx, length(colors))};
                        [~, shortLabel] = strtok(rightYChan.Label, '/');
                        if isempty(shortLabel)
                            ryDisplayName = rightYChan.Label;
                        else
                            ryDisplayName = strtrim(shortLabel(2:end));
                        end
                        rx{end+1} = ryX; ry{end+1} = rySig;
                        rl{end+1} = ryDisplayName; rc{end+1} = rightColor;
                    end
                end
                rightYData = struct('x', {rx}, 'y', {ry}, 'labels', {rl}, 'colors', {rc});
            end

            obj.View.RenderWaveform(axesIdx, xCell, yCell, labels, colorList, rightYData);
        end

        function [sig, xSig] = SliceChannel(~, chan, xRaw, hasXChannel)
        % SliceChannel 对通道数据和横轴数据做切片并对齐
            if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                sr = chan.SliceRange;
                sig = ChannelOperations.ApplySlice(chan.Data, sr(1), sr(2));
                if hasXChannel
                    xSig = ChannelOperations.ApplySlice(xRaw, sr(1), sr(2));
                    n = min(length(xSig), length(sig));
                    xSig = xSig(1:n);
                    sig = sig(1:n);
                else
                    xSig = (0:length(sig)-1)';
                end
            else
                sig = chan.Data;
                if hasXChannel
                    n = min(length(xRaw), length(sig));
                    xSig = xRaw(1:n);
                    sig = sig(1:n);
                else
                    xSig = (0:length(sig)-1)';
                end
            end
        end

        function chan = FindChannelInList(~, chans, datasetIdx, colIdx)
        % FindChannelInList 在通道列表中查找指定通道
            chan = [];
            for i = 1:length(chans)
                if chans{i}.DatasetIdx == datasetIdx && chans{i}.ColIdx == colIdx
                    chan = chans{i};
                    return;
                end
            end
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
        % GetChannelState 通道在聚焦 axes 上的状态与标记（切片/横轴/右Y轴）
            isChecked = false;
            sliceTag = '';
            axIdx = obj.View.GetFocusedAxes();
            chans = obj.Session.GetAxesChannels(axIdx);
            for sc = 1:length(chans)
                if chans{sc}.DatasetIdx == datasetIdx && chans{sc}.ColIdx == colIdx
                    isChecked = true;
                    if isfield(chans{sc}, 'SliceRange') && ~isempty(chans{sc}.SliceRange)
                        sr = chans{sc}.SliceRange;
                        totalN = length(chans{sc}.Data);
                        segLen = sr(2) - sr(1) + 1;
                        if sr(1) > 1 || sr(2) < totalN || sr(2) > totalN
                            sliceTag = [sliceTag sprintf(' [%d~%d L%d]', sr(1), sr(2), segLen)]; %#ok<AGROW>
                        end
                    end
                    % 横轴/右Y轴标记（仅在通道勾选时显示）
                    [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
                    if ~isempty(xDsIdx) && xDsIdx == datasetIdx && xColIdx == colIdx
                        sliceTag = [sliceTag ' [X]'];
                    end
                    refs = obj.Session.GetRightYChannel(axIdx);
                    for ri = 1:length(refs)
                        if refs{ri}.DatasetIdx == datasetIdx && refs{ri}.ColIdx == colIdx
                            sliceTag = [sliceTag ' [R]'];
                            break;
                        end
                    end
                    break;
                end
            end
        end

        % ---- axes 增删与清图 ----

        function OnAxesRemove(obj, ~, ~)
            obj.Session.RemoveAxes(obj.View.GetAxesCount() + 1);
            obj.SyncViewAxisState(obj.View.GetFocusedAxes());
            obj.RefreshChannelTable();
        end

        function OnClearPlot(obj, ~, ~)
            obj.View.ClearAllAxes();
            for a = 1:obj.Session.AxesSlotCount
                obj.Session.ClearAxes(a);
            end
            obj.SyncViewAxisState(obj.View.GetFocusedAxes());
            obj.RefreshChannelTable();
        end

        % ---- 横轴/右Y轴 ----

        function OnSetXAxis(obj, ~, evt)
        % OnSetXAxis 设置当前聚焦 axes 的横轴通道
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();

            % 禁止同通道同时为横轴和右Y
            refs = obj.Session.GetRightYChannel(axIdx);
            for i = 1:length(refs)
                if refs{i}.DatasetIdx == d.datasetIdx && refs{i}.ColIdx == d.colIdx
                    obj.View.ShowError('该通道已设为右 Y 轴，请先恢复');
                    return;
                end
            end

            obj.Session.SetXChannel(axIdx, d.datasetIdx, d.colIdx);
            obj.SyncViewAxisState(axIdx);
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
            dsName = obj.Session.GetDatasetName(d.datasetIdx);
            ds = obj.Session.GetDataset(d.datasetIdx);
            colName = ds.GetColumnName(d.colIdx);
            obj.StatusCallback(sprintf('  Axes %d 横轴 → %s / %s', axIdx, dsName, colName));
        end

        function OnClearXAxis(obj, ~, ~)
        % OnClearXAxis 恢复当前聚焦 axes 默认横轴
            axIdx = obj.View.GetFocusedAxes();
            obj.Session.ClearXChannel(axIdx);
            obj.SyncViewAxisState(axIdx);
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
            obj.StatusCallback(sprintf('  Axes %d 横轴 → 默认', axIdx));
        end

        function OnSetRightYAxis(obj, ~, evt)
        % OnSetRightYAxis 设置当前聚焦 axes 的右Y轴通道
            d = evt.Data;
            axIdx = obj.View.GetFocusedAxes();

            % 禁止同通道同时为横轴和右Y
            [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
            if ~isempty(xDsIdx) && xDsIdx == d.datasetIdx && xColIdx == d.colIdx
                obj.View.ShowError('该通道已设为横轴，请先恢复');
                return;
            end

            obj.Session.SetRightYChannel(axIdx, d.datasetIdx, d.colIdx);
            obj.SyncViewAxisState(axIdx);
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
        end

        function OnClearRightYAxis(obj, ~, ~)
        % OnClearRightYAxis 恢复当前聚焦 axes 单Y轴模式
            axIdx = obj.View.GetFocusedAxes();
            obj.Session.ClearRightYChannel(axIdx);
            obj.SyncViewAxisState(axIdx);
            obj.RenderAxes(axIdx);
            obj.RefreshChannelTable();
        end

        function SyncViewAxisState(obj, axIdx)
        % SyncViewAxisState 将 Session 的横轴/右Y轴状态同步到 View
            [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
            refs = obj.Session.GetRightYChannel(axIdx);
            rightYList = cell(1, length(refs));
            for i = 1:length(refs)
                rightYList{i} = [refs{i}.DatasetIdx, refs{i}.ColIdx];
            end
            obj.View.UpdateAxisChannelState(axIdx, xDsIdx, xColIdx, rightYList);

            % 同步归一化下拉框
            normMode = obj.Session.GetAxesNormMode(axIdx);
            modeMap = containers.Map({'none','minmax','zscore','meanzero'}, ...
                {'None','Min-Max','Z-Score','Mean Zero'});
            if modeMap.isKey(normMode)
                obj.View.NormDropdown.Value = modeMap(normMode);
            end
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

            % 获取横轴数据（用于物理坐标→数据掩码映射）
            [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
            hasXChannel = ~isempty(xDsIdx);
            if hasXChannel
                xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
            end

            chans = obj.Session.GetAxesChannels(axIdx);
            if isempty(chans)
                normParams = struct();
                return;
            end

            channelStats = {};
            for i = 1:length(chans)
                chan = chans{i};
                % 切片
                if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                    sr = chan.SliceRange;
                    sig = ChannelOperations.ApplySlice(chan.Data, sr(1), sr(2));
                    if hasXChannel
                        xSig = ChannelOperations.ApplySlice(xRaw, sr(1), sr(2));
                        n = min(length(xSig), length(sig));
                        xSig = xSig(1:n); sig = sig(1:n);
                    end
                else
                    sig = chan.Data;
                    if hasXChannel
                        n = min(length(xRaw), length(sig));
                        xSig = xRaw(1:n); sig = sig(1:n);
                    end
                end

                if hasXChannel
                    % 逻辑索引：物理坐标范围 → 数据子集
                    mask = xSig >= xl(1) & xSig <= xl(2);
                    refSig = sig(mask);
                    if isempty(refSig)
                        refSig = sig;  % fallback
                    end
                    s = struct();
                    s.minY = min(refSig);
                    s.maxY = max(refSig);
                    s.meanY = mean(refSig);
                    s.stdY = std(refSig);
                else
                    % 传统模式：xlim 直接是索引范围
                    refStart = max(1, round(xl(1)));
                    refEnd = round(xl(2));
                    if isfield(chan, 'SliceRange') && ~isempty(chan.SliceRange)
                        sliceStart = chan.SliceRange(1);
                    else
                        sliceStart = 1;
                    end
                    s = ChannelOperations.ComputeStats(chan.Data, refStart, refEnd, sliceStart);
                end
                channelStats{end+1} = s; %#ok<AGROW>
            end

            normParams = struct();
            normParams.refWindow = xl;
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

            result = obj.View.ShowSliceRangeDialog(colName, totalRows, currentRange(1), currentLen);
            if isempty(result), return; end
            startRow = result(1);
            segLen = result(2);

            if startRow > totalRows
                obj.View.ShowError(sprintf('起点 %d 超过数据总行数 %d', startRow, totalRows));
                return;
            end
            endRow = startRow + segLen - 1;
            if segLen > totalRows
                obj.View.ShowError(sprintf('切片长度 %d 超过数据总行数 %d', segLen, totalRows));
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

            obj.RenameChannel(d.datasetIdx, d.colIdx, newName);
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

            obj.RenameChannel(d.datasetIdx, d.colIdx, newName);
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

            matPath = obj.Session.GetDatasetPath(d.datasetIdx);
            if ~isempty(matPath)
                DataReaderFactory.UpdateDatasetNameInMat(matPath, newName);
            end

            obj.RefreshChannelTable();
            obj.RenderAxes(obj.View.GetFocusedAxes());
        end

        function sampleRate = EnsureSampleRate(obj, datasetIdx)
        % EnsureSampleRate 采样率为空时弹窗设置并回写磁盘；取消返回 []
            ds = obj.Session.GetDataset(datasetIdx);
            sampleRate = ds.SampleRate;
            if ~isempty(sampleRate)
                return;
            end
            dsName = obj.Session.GetDatasetName(datasetIdx);
            newRate = obj.View.ShowSampleRateDialog(dsName);
            if isempty(newRate), return; end
            obj.SetSampleRate(datasetIdx, newRate);
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
            newRate = obj.View.ShowSampleRateDialog(dsName, default);
            if isempty(newRate), return; end
            obj.SetSampleRate(d.datasetIdx, newRate);
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
            [xDsIdx, xColIdx] = obj.Session.GetXChannel(axIdx);
            hasXChannel = ~isempty(xDsIdx);
            xRaw = [];
            if hasXChannel
                xRaw = obj.Session.GetDataset(xDsIdx).GetColumn(xColIdx);
            end

            % View 创建弹窗 UI
            h = obj.View.CreateSpectrumPopup();
            obj.TrackPopup(h.fig);
            h.fig.CloseRequestFcn = @(s, e) obj.RemovePopup(h.fig);

            ax1 = h.axTime; ax2 = h.axFreq;
            hold(ax1, 'on'); hold(ax2, 'on');

            nPlotted = 0;
            for c = 1:length(chans)
                chan = chans{c};
                sampleRate = obj.EnsureSampleRate(chan.DatasetIdx);
                if isempty(sampleRate) || isnan(sampleRate) || sampleRate <= 0
                    continue;
                end

                [sig, xSig] = ChannelOperations.SliceAndAlign(...
                    chan.Data, xRaw, chan.SliceRange, hasXChannel);
                sig = obj.ApplyNorm(axIdx, c, sig);

                chanColor = colors{obj.ChannelColorIndex(chan.DatasetIdx, chan.ColIdx, length(colors))};
                chanLabel = chan.Label;
                nPlotted = nPlotted + 1;
                plot(ax1, xSig, sig, 'Color', chanColor, 'DisplayName', chanLabel);

                switch lower(analysisType)
                    case 'fft'
                        [P1, freq] = SignalProcessor.ComputeFFTSingleSided(sig, sampleRate);
                        if abs(freq(1)) < eps
                            semilogx(ax2, freq(2:end), P1(2:end), 'Color', chanColor, 'DisplayName', chanLabel);
                        else
                            semilogx(ax2, freq, P1, 'Color', chanColor, 'DisplayName', chanLabel);
                        end
                    case 'psd'
                        [rmsAmp, freq, totalRms] = SignalProcessor.ComputeRMSSpectrum(sig, sampleRate);
                        label = sprintf('%s (RMS=%.4f)', chanLabel, totalRms);
                        if abs(freq(1)) < eps
                            semilogx(ax2, freq(2:end), rmsAmp(2:end), 'Color', chanColor, 'DisplayName', label);
                        else
                            semilogx(ax2, freq, rmsAmp, 'Color', chanColor, 'DisplayName', label);
                        end
                end
            end

            hold(ax1, 'off'); hold(ax2, 'off');
            if hasXChannel
                dsName = obj.Session.GetDatasetName(xDsIdx);
                ds = obj.Session.GetDataset(xDsIdx);
                xlabel(ax1, sprintf('%s / %s', dsName, ds.GetColumnName(xColIdx)));
            else
                xlabel(ax1, 'Sample Index');
            end
            ylabel(ax1, 'Amplitude');
            title(ax1, 'Time Domain Signal');
            grid(ax1, 'on');
            ax2.XScale = 'log';
            xlabel(ax2, 'Frequency (Hz)');
            grid(ax2, 'on');
            if strcmpi(analysisType, 'fft')
                ax2.YScale = 'linear';
                ylabel(ax2, 'Amplitude');
                title(ax2, 'Single-Sided Amplitude Spectrum');
            else
                ax2.YScale = 'log';
                ylabel(ax2, 'RMS Amplitude');
                title(ax2, 'RMS Spectrum (per frequency bin)');
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

            opKeys  = {'add', 'sub', 'mul', 'div', ...
                       'diff', 'cumsum', 'abs', 'square', 'sqrt', ...
                       'log10', 'detrend', 'rms', 'smooth'};

            % View 创建对话框 UI
            h = obj.View.CreateCalcDialog(channelList);
            dlg = h.fig;
            obj.TrackPopup(dlg);
            dlg.CloseRequestFcn = @(s, e) obj.RemovePopup(dlg);

            % 绑定回调
            h.opPopup.ValueChangedFcn = @(s, e) updateOpType();
            h.popupA.ValueChangedFcn = @(s, e) updateOpType();
            h.btnOk.ButtonPushedFcn = @(s, e) doCalc();
            h.btnCancel.ButtonPushedFcn = @(s, e) obj.RemovePopup(dlg);

            updateOpType();

            function updateOpType()
                val = find(strcmp(h.opPopup.Value, h.opPopup.Items), 1);
                if isempty(val), val = 1; end
                key = opKeys{val};
                isDual = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));
                isSmooth = strcmp(key, 'smooth');

                if isDual
                    h.popupB.Enable = 'on'; h.editB1.Enable = 'on'; h.editB2.Enable = 'on';
                else
                    h.popupB.Enable = 'off'; h.editB1.Enable = 'off'; h.editB2.Enable = 'off';
                end
                if isSmooth
                    h.winLabel.Visible = 'on'; h.editWin.Visible = 'on';
                else
                    h.winLabel.Visible = 'off'; h.editWin.Visible = 'off';
                end

                idxA = find(strcmp(h.popupA.Value, channelList), 1);
                if isempty(idxA), idxA = 1; end
                nameA = strrep(channelList{idxA}, ' > ', '_');
                if isDual
                    idxB = find(strcmp(h.popupB.Value, channelList), 1);
                    if isempty(idxB), idxB = 1; end
                    nameB = strrep(channelList{idxB}, ' > ', '_');
                    ops = {'+', '-', '×', '÷'};
                    defaultName = sprintf('%s%s%s', nameA, ops{val}, nameB);
                else
                    opNames = {'diff', 'cumsum', 'abs', 'sq', 'sqrt', 'log10', 'detrend', 'rms', 'smooth'};
                    defaultName = sprintf('%s(%s)', opNames{val - 4}, nameA);
                end
                if length(defaultName) > 63, defaultName = defaultName(1:63); end
                h.editName.Value = defaultName;

                if idxA <= size(channelMap, 1)
                    dsA = obj.Session.GetDataset(channelMap(idxA, 1));
                    h.editA2.Value = max(1, dsA.RowCount);
                end
                if isDual && idxB <= size(channelMap, 1)
                    dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                    h.editB2.Value = max(1, dsB.RowCount);
                end
            end

            function doCalc()
                try
                    val = find(strcmp(h.opPopup.Value, h.opPopup.Items), 1);
                    if isempty(val), val = 1; end
                    key = opKeys{val};
                    isDual = any(strcmp(key, {'add', 'sub', 'mul', 'div'}));

                    idxA = find(strcmp(h.popupA.Value, channelList), 1);
                    if isempty(idxA), idxA = 1; end
                    dsIdxA = channelMap(idxA, 1);
                    dsA = obj.Session.GetDataset(dsIdxA);
                    dataA = dsA.GetColumn(channelMap(idxA, 2));
                    a1 = max(1, round(h.editA1.Value));
                    aLen = max(1, min(round(h.editA2.Value), size(dataA,1) - a1 + 1));
                    dataA = dataA(a1 : a1 + aLen - 1);

                    params = struct();
                    if isDual
                        idxB = find(strcmp(h.popupB.Value, channelList), 1);
                        if isempty(idxB), idxB = 1; end
                        dsB = obj.Session.GetDataset(channelMap(idxB, 1));
                        dataB = dsB.GetColumn(channelMap(idxB, 2));
                        b1 = max(1, round(h.editB1.Value));
                        bLen = max(1, min(round(h.editB2.Value), size(dataB,1) - b1 + 1));
                        dataB = dataB(b1 : b1 + bLen - 1);
                        if length(dataA) ~= length(dataB)
                            obj.View.ShowError(sprintf('窗口长度不一致: A=%d, B=%d', length(dataA), length(dataB)));
                            return;
                        end
                    else
                        dataB = [];
                        switch key
                            case {'diff', 'cumsum'}
                                params.sampleRate = obj.RequireSampleRateForCalc(dsIdxA);
                            case 'smooth'
                                params.windowSize = round(h.editWin.Value);
                        end
                    end

                    if strcmp(key, 'rms')
                        rmsVal = ChannelOperations.Compute('rms', dataA, [], params);
                        obj.View.ShowInfo(sprintf('RMS = %.6g', rmsVal));
                        obj.RemovePopup(dlg);
                        return;
                    end

                    result = ChannelOperations.Compute(key, dataA, dataB, params);
                    resultName = strtrim(h.editName.Value);
                    if isempty(resultName)
                        resultName = sprintf('calc_%d', obj.Session.DatasetCount + 1);
                    end

                    tempDir = tempname; mkdir(tempDir);
                    matPath = DataReaderFactory.SaveStandard(result, {resultName}, tempDir, resultName, 'calc', 'calc');
                    newDs = DataReaderFactory.LoadStandard(matPath);
                    obj.Session.AddDataset(newDs, resultName, matPath);
                    obj.RefreshChannelTable();
                    obj.RemovePopup(dlg);
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
        % OnExportFigure 导出全部 axes 到独立 legacy figure（支持双Y轴和自定义横轴）
            n = obj.View.GetAxesCount();
            if n == 0
                return;
            end
            fig = obj.View.CreateExportFigure('Export');
            obj.TrackPopup(fig);
            fig.CloseRequestFcn = @(s, e) obj.RemovePopup(fig);

            for i = 1:n
                ax = obj.View.GetAxes(i);
                sub = subplot(n, 1, i, 'Parent', fig);

                % 按 Tag 过滤左右Y线（避免 findobj 返回全部线）
                allSrcLines = findobj(ax, 'Type', 'line');
                leftSrc = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'leftY'), allSrcLines));
                rightSrc = allSrcLines(arrayfun(@(l) strcmp(l.Tag, 'rightY'), allSrcLines));
                hasRightY = ~isempty(rightSrc);

                if hasRightY
                    % 左 Y → 导出 figure
                    yyaxis(sub, 'left');
                    hold(sub, 'on');
                    subLeftLines = gobjects(0);
                    for k = 1:numel(leftSrc)
                        l = leftSrc(k);
                        h = plot(sub, l.XData, l.YData, ...
                            'Color', l.Color, 'LineStyle', l.LineStyle, ...
                            'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                            'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                        subLeftLines(end+1) = h;
                    end
                    hold(sub, 'off');
                    yyaxis(ax, 'left');
                    ylabel(sub, get(get(ax, 'YLabel'), 'String'));

                    % 右 Y → 导出 figure
                    yyaxis(sub, 'right');
                    hold(sub, 'on');
                    subRightLines = gobjects(0);
                    for k = 1:numel(rightSrc)
                        l = rightSrc(k);
                        h = plot(sub, l.XData, l.YData, ...
                            'Color', l.Color, 'LineStyle', l.LineStyle, ...
                            'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                            'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                        subRightLines(end+1) = h;
                    end
                    hold(sub, 'off');
                    yyaxis(ax, 'right');
                    ylabel(sub, get(get(ax, 'YLabel'), 'String'));
                    yyaxis(ax, 'left');  % 恢复源 axes 活动侧

                    subAllLines = [subLeftLines, subRightLines];
                    yyaxis(sub, 'left');
                else
                    hold(sub, 'on');
                    subAllLines = gobjects(0);
                    for k = 1:numel(allSrcLines)
                        l = allSrcLines(k);
                        h = plot(sub, l.XData, l.YData, ...
                            'Color', l.Color, 'LineStyle', l.LineStyle, ...
                            'LineWidth', l.LineWidth, 'Marker', l.Marker, ...
                            'MarkerSize', l.MarkerSize, 'DisplayName', l.DisplayName);
                        subAllLines(end+1) = h;
                    end
                    hold(sub, 'off');
                    ylabel(sub, get(get(ax, 'YLabel'), 'String'));
                end

                grid(sub, 'on');
                title(sub, get(get(ax, 'Title'), 'String'));

                % X 轴标签（所有子图，含列名）
                [xDsIdx, xColIdx] = obj.Session.GetXChannel(i);
                if ~isempty(xDsIdx)
                    ds = obj.Session.GetDataset(xDsIdx);
                    dsName = obj.Session.GetDatasetName(xDsIdx);
                    xlabel(sub, sprintf('%s / %s', dsName, ds.GetColumnName(xColIdx)));
                else
                    xlabel(sub, 'Sample Index');
                end

                if numel(subAllLines) > 1
                    legend(sub, subAllLines, 'Location', 'best', 'Interpreter', 'none');
                end
            end
        end

        function OnExportDatasetExcel(obj, ~, evt)
        % OnExportDatasetExcel 手动导出数据集为 Excel（_review.xlsx）
            d = evt.Data;
            matPath = obj.Session.GetDatasetPath(d.datasetIdx);
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
        % OnAxesClicked 点击 axes：更新状态栏坐标 + 同步横轴/右Y轴菜单状态
            d = evt.Data;
            if d.axesIdx > 0
                % 同步横轴/右Y轴状态到 View（供右键菜单使用）
                obj.SyncViewAxisState(d.axesIdx);

                % 状态栏显示
                [xDsIdx, ~] = obj.Session.GetXChannel(d.axesIdx);
                if ~isempty(xDsIdx)
                    dsName = obj.Session.GetDatasetName(xDsIdx);
                    obj.StatusCallback(sprintf('  Axes %d  |  X = %.6g (%s)  |  Y = %.6g', ...
                        d.axesIdx, d.x, dsName, d.y));
                else
                    obj.StatusCallback(sprintf('  Axes %d  |  X = %.6g  |  Y = %.6g', ...
                        d.axesIdx, d.x, d.y));
                end
            else
                obj.StatusCallback(' ');
            end
            % 仅在聚焦 axes 变化时重建通道表（避免每次点击都重建）
            if d.axesIdx ~= obj.LastFocusedAxes_
                obj.LastFocusedAxes_ = d.axesIdx;
                obj.RefreshChannelTable();
            end
        end

        % ---- 共享 Helper ----

        function SetSampleRate(obj, datasetIdx, newRate)
        % SetSampleRate 更新采样率：Session + .mat + JSON
            obj.Session.UpdateSampleRate(datasetIdx, newRate);
            matPath = obj.Session.GetDatasetPath(datasetIdx);
            if ~isempty(matPath) && exist(matPath, 'file')
                DataReaderFactory.UpdateSampleRateInMat(matPath, newRate);
            end
        end

        function RenameChannel(obj, datasetIdx, colIdx, newName)
        % RenameChannel 重命名通道：Session + .mat + JSON
            ds = obj.Session.GetDataset(datasetIdx);
            newNames = ds.ColumnNames;
            newNames{colIdx} = newName;
            newDs = ds.RebuildWithColumnNames(newNames);
            obj.Session.UpdateDataset(datasetIdx, newDs);

            matPath = obj.Session.GetDatasetPath(datasetIdx);
            if ~isempty(matPath)
                DataReaderFactory.UpdateColumnNamesInMat(matPath, newNames);
            end
        end

        function idx = ChannelColorIndex(~, datasetIdx, colIdx, nColors)
        % ChannelColorIndex 通道→颜色索引（基于 datasetIdx+colIdx 哈希，与序号无关）
            idx = mod((datasetIdx - 1) * 7 + colIdx, nColors) + 1;
        end

    end
end
