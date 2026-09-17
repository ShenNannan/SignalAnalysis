classdef SessionData < handle
% SessionData - 会话状态容器
%
% 支持多数据集（多文件/子文件夹），通道叠加到 axes。
% handle class，支持事件通知。

    properties (SetAccess = private)
        Datasets_       cell      % {Dataset1, Dataset2, ...}
        DatasetNames_   cell      % {'Test1', 'Test2', ...}
        DatasetPaths_   cell      % {path1, path2, ...}
        AxesData_       cell      % 每个 axes 的通道列表 struct
        AxesNormMode_   cell      % 每个 axes 的归一化模式
        MaxAxes_        double    % axes 数量上限
        LastPaths_      cell      % 最近使用的路径
        AxesNormParams_     cell  % 每个 axes 的归一化参数 struct
        AxesXChannel_       cell  % 每个 axes 的横轴引用 {struct|[], ...} struct: .DatasetIdx .ColIdx
        AxesRightYChannel_  cell  % 每个 axes 的右Y轴引用 {{struct, struct, ...}|{}, ...} struct: .DatasetIdx .ColIdx
    end

    properties (Dependent, SetAccess = private)
        DatasetCount    double    % 数据集数量
        AxesCount       double    % 当前 axes 数量（有通道的）
        AxesSlotCount   double    % axes 槽位总数（含空槽）
    end

    events
        DatasetsUpdated  % 数据集变更（增删）
        ChannelsUpdated  % axes 通道变更
    end

    methods
        function obj = SessionData(maxAxes)
        % SessionData 构造函数
            if nargin < 1
                maxAxes = 6;
            end
            obj.MaxAxes_ = maxAxes;
            obj.Datasets_ = {};
            obj.DatasetNames_ = {};
            obj.DatasetPaths_ = {};
            obj.AxesData_ = {};
            obj.AxesNormMode_ = {};
            obj.LastPaths_ = cell(1, 4);
            obj.AxesNormParams_ = {};
            obj.AxesXChannel_ = {};
            obj.AxesRightYChannel_ = {};
        end

        % ---- 数据集管理 ----

        function AddDataset(obj, dataset, name, path)
        % AddDataset 追加数据集
            obj.Datasets_{end+1} = dataset;
            obj.DatasetNames_{end+1} = name;
            obj.DatasetPaths_{end+1} = path;
            notify(obj, 'DatasetsUpdated');
        end

        function RemoveDataset(obj, idx)
        % RemoveDataset 移除指定数据集
            if idx < 1 || idx > obj.DatasetCount
                return;
            end
            obj.Datasets_(idx) = [];
            obj.DatasetNames_(idx) = [];
            obj.DatasetPaths_(idx) = [];

            % 更新 axes 中引用该数据集的通道：移除或调整索引
            for a = 1:length(obj.AxesData_)
                if isempty(obj.AxesData_{a}), continue; end
                chans = obj.AxesData_{a}.Channels;
                keep = true(1, length(chans));
                for c = 1:length(chans)
                    if chans{c}.DatasetIdx == idx
                        keep(c) = false;
                    elseif chans{c}.DatasetIdx > idx
                        chans{c}.DatasetIdx = chans{c}.DatasetIdx - 1;
                    end
                end
                obj.AxesData_{a}.Channels = chans(keep);
            end

            % 清理横轴/右Y轴引用
            for a = 1:length(obj.AxesXChannel_)
                if ~isempty(obj.AxesXChannel_{a}) && obj.AxesXChannel_{a}.DatasetIdx == idx
                    obj.AxesXChannel_{a} = [];
                elseif ~isempty(obj.AxesXChannel_{a}) && obj.AxesXChannel_{a}.DatasetIdx > idx
                    obj.AxesXChannel_{a}.DatasetIdx = obj.AxesXChannel_{a}.DatasetIdx - 1;
                end
            end
            for a = 1:length(obj.AxesRightYChannel_)
                refs = obj.AxesRightYChannel_{a};
                if isempty(refs), continue; end
                keep = {};
                for r = 1:length(refs)
                    if refs{r}.DatasetIdx == idx
                        % 被删数据集的引用，跳过（不保留）
                    elseif refs{r}.DatasetIdx > idx
                        refs{r}.DatasetIdx = refs{r}.DatasetIdx - 1;
                        keep{end+1} = refs{r}; %#ok<AGROW>
                    else
                        keep{end+1} = refs{r}; %#ok<AGROW>
                    end
                end
                obj.AxesRightYChannel_{a} = keep;
            end

            notify(obj, 'DatasetsUpdated');
        end

        function ClearAllDatasets(obj)
        % ClearAllDatasets 清空所有数据集
            obj.Datasets_ = {};
            obj.DatasetNames_ = {};
            obj.DatasetPaths_ = {};
            obj.AxesData_ = {};
            obj.AxesNormMode_ = {};
            obj.AxesNormParams_ = {};
            obj.AxesXChannel_ = {};
            obj.AxesRightYChannel_ = {};
            notify(obj, 'DatasetsUpdated');
            notify(obj, 'ChannelsUpdated');
        end

        function UpdateDataset(obj, idx, newDataset)
        % UpdateDataset 替换指定数据集，同步更新通道数据
            if idx < 1 || idx > obj.DatasetCount
                return;
            end
            obj.Datasets_{idx} = newDataset;

            % 更新 axes 中引用该数据集的通道数据
            for a = 1:length(obj.AxesData_)
                if isempty(obj.AxesData_{a}), continue; end
                for c = 1:length(obj.AxesData_{a}.Channels)
                    ch = obj.AxesData_{a}.Channels{c};
                    if ch.DatasetIdx == idx && ch.ColIdx <= newDataset.ColumnCount
                        obj.AxesData_{a}.Channels{c}.Data = newDataset.GetColumn(ch.ColIdx);
                        obj.AxesData_{a}.Channels{c}.Label = [obj.DatasetNames_{idx} ' / ' newDataset.GetDisplayLabel(ch.ColIdx)];
                    end
                end
            end
            notify(obj, 'DatasetsUpdated');
        end

        function SetDatasetName(obj, idx, newName)
        % SetDatasetName 重命名数据集，同步更新 axes 中的通道标签
            if idx < 1 || idx > obj.DatasetCount
                return;
            end
            obj.DatasetNames_{idx} = newName;
            ds = obj.Datasets_{idx};
            for a = 1:length(obj.AxesData_)
                if isempty(obj.AxesData_{a}), continue; end
                for c = 1:length(obj.AxesData_{a}.Channels)
                    ch = obj.AxesData_{a}.Channels{c};
                    if ch.DatasetIdx == idx && ch.ColIdx <= ds.ColumnCount
                        obj.AxesData_{a}.Channels{c}.Label = [newName ' / ' ds.GetDisplayLabel(ch.ColIdx)];
                    end
                end
            end
            notify(obj, 'DatasetsUpdated');
        end

        function ds = GetDataset(obj, idx)
        % GetDataset 获取指定数据集
            if idx < 1 || idx > obj.DatasetCount
                error('SignalAnalysis:SessionData:IndexOutOfBounds', ...
                    'Dataset index %d out of range [1, %d]', idx, obj.DatasetCount);
            end
            ds = obj.Datasets_{idx};
        end

        function name = GetDatasetName(obj, idx)
        % GetDatasetName 获取数据集名称
            if idx < 1 || idx > obj.DatasetCount
                name = '';
            else
                name = obj.DatasetNames_{idx};
            end
        end

        function path = GetDatasetPath(obj, idx)
        % GetDatasetPath 获取数据集路径
            if idx < 1 || idx > length(obj.DatasetPaths_)
                path = '';
            else
                path = obj.DatasetPaths_{idx};
            end
        end

        % ---- Axes 通道管理 ----

        function AddChannelToAxes(obj, axesIdx, datasetIdx, colIdx)
        % AddChannelToAxes 将通道叠加到指定 axes
            if axesIdx < 1 || axesIdx > obj.MaxAxes_
                error('SignalAnalysis:SessionData:InvalidAxesIndex', ...
                    'Axes index %d out of range [1, %d]', axesIdx, obj.MaxAxes_);
            end
            if datasetIdx < 1 || datasetIdx > obj.DatasetCount
                return;
            end

            ds = obj.Datasets_{datasetIdx};
            if colIdx < 1 || colIdx > ds.ColumnCount
                return;
            end

            % 扩展所有 axes 容器到目标索引
            obj.ensureAxesCapacity(axesIdx);
            if isempty(obj.AxesData_{axesIdx})
                obj.AxesData_{axesIdx} = struct('Channels', {{}});
            end

            % 检查是否已存在
            chans = obj.AxesData_{axesIdx}.Channels;
            for c = 1:length(chans)
                if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                    return; % 已存在，不重复添加
                end
            end

            % 添加通道
            chan = struct();
            chan.DatasetIdx = datasetIdx;
            chan.ColIdx = colIdx;
            chan.Data = ds.GetColumn(colIdx);
            chan.Label = [obj.DatasetNames_{datasetIdx} ' / ' ds.GetDisplayLabel(colIdx)];
            chan.SliceRange = [1, size(chan.Data, 1)];
            obj.AxesData_{axesIdx}.Channels{end+1} = chan;

            notify(obj, 'ChannelsUpdated');
        end

        function RemoveChannelFromAxes(obj, axesIdx, datasetIdx, colIdx)
        % RemoveChannelFromAxes 从 axes 移除指定通道
            if axesIdx < 1 || axesIdx > length(obj.AxesData_)
                return;
            end
            if isempty(obj.AxesData_{axesIdx})
                return;
            end

            chans = obj.AxesData_{axesIdx}.Channels;
            keep = true(1, length(chans));
            for c = 1:length(chans)
                if chans{c}.DatasetIdx == datasetIdx && chans{c}.ColIdx == colIdx
                    keep(c) = false;
                end
            end
            obj.AxesData_{axesIdx}.Channels = chans(keep);

            % 若被移除的通道是横轴或右Y轴引用，自动清除
            if axesIdx <= length(obj.AxesXChannel_) && ~isempty(obj.AxesXChannel_{axesIdx})
                ref = obj.AxesXChannel_{axesIdx};
                if ref.DatasetIdx == datasetIdx && ref.ColIdx == colIdx
                    obj.AxesXChannel_{axesIdx} = [];
                end
            end
            if axesIdx <= length(obj.AxesRightYChannel_) && ~isempty(obj.AxesRightYChannel_{axesIdx})
                refs = obj.AxesRightYChannel_{axesIdx};
                newRefs = {};
                for r = 1:length(refs)
                    if ~(refs{r}.DatasetIdx == datasetIdx && refs{r}.ColIdx == colIdx)
                        newRefs{end+1} = refs{r}; %#ok<AGROW>
                    end
                end
                obj.AxesRightYChannel_{axesIdx} = newRefs;
            end

            notify(obj, 'ChannelsUpdated');
        end

        function ClearAxes(obj, axesIdx)
        % ClearAxes 清空指定 axes 的所有通道
            if axesIdx >= 1 && axesIdx <= length(obj.AxesData_)
                obj.AxesData_{axesIdx} = struct('Channels', {{}});
            end
            % 同步清除横轴/右Y轴引用
            if axesIdx >= 1 && axesIdx <= length(obj.AxesXChannel_)
                obj.AxesXChannel_{axesIdx} = [];
            end
            if axesIdx >= 1 && axesIdx <= length(obj.AxesRightYChannel_)
                obj.AxesRightYChannel_{axesIdx} = {};
            end
            notify(obj, 'ChannelsUpdated');
        end

        function chans = GetAxesChannels(obj, axesIdx)
        % GetAxesChannels 获取 axes 的通道列表
            if axesIdx < 1 || axesIdx > length(obj.AxesData_) || isempty(obj.AxesData_{axesIdx})
                chans = {};
            else
                chans = obj.AxesData_{axesIdx}.Channels;
            end
        end

        % ---- Axes 数量管理 ----

        function RemoveAxes(obj, idx)
        % RemoveAxes 移除指定 axes 的通道
            if idx >= 1 && idx <= length(obj.AxesData_)
                obj.AxesData_{idx} = struct('Channels', {{}});
            end
            if idx >= 1 && idx <= length(obj.AxesNormMode_)
                obj.AxesNormMode_{idx} = 'none';
            end
            if idx >= 1 && idx <= length(obj.AxesNormParams_)
                obj.AxesNormParams_{idx} = struct();
            end
            if idx >= 1 && idx <= length(obj.AxesXChannel_)
                obj.AxesXChannel_{idx} = [];
            end
            if idx >= 1 && idx <= length(obj.AxesRightYChannel_)
                obj.AxesRightYChannel_{idx} = {};
            end
            notify(obj, 'ChannelsUpdated');
        end

        % ---- 采样率 ----

        function UpdateSampleRate(obj, datasetIdx, newRate)
        % UpdateSampleRate 用新采样率重建指定数据集
            if datasetIdx < 1 || datasetIdx > obj.DatasetCount
                return;
            end
            obj.Datasets_{datasetIdx} = obj.Datasets_{datasetIdx}.RebuildWithSampleRate(newRate);

            % 更新 axes 中引用该数据集的通道数据
            for a = 1:length(obj.AxesData_)
                if isempty(obj.AxesData_{a}), continue; end
                chans = obj.AxesData_{a}.Channels;
                for c = 1:length(chans)
                    if chans{c}.DatasetIdx == datasetIdx
                        chans{c}.Data = obj.Datasets_{datasetIdx}.GetColumn(chans{c}.ColIdx);
                    end
                end
            end
            notify(obj, 'DatasetsUpdated');
        end

        function sr = GetSampleRate(obj, datasetIdx)
        % GetSampleRate 读取指定数据集的采样率
            sr = [];
            if datasetIdx < 1 || datasetIdx > obj.DatasetCount
                return;
            end
            ds = obj.Datasets_{datasetIdx};
            if isprop(ds, 'SampleRate')
                sr = ds.SampleRate;
            end
        end

        % ---- 通道切片 ----

        function SetChannelSlice(obj, axesIdx, chanIdx, startRow, endRow)
        % SetChannelSlice 设置通道的独立切片范围（支持环形缓冲，endRow 可超过数据长度）
            if axesIdx < 1 || axesIdx > length(obj.AxesData_) || isempty(obj.AxesData_{axesIdx})
                return;
            end
            chans = obj.AxesData_{axesIdx}.Channels;
            if chanIdx < 1 || chanIdx > length(chans)
                return;
            end
            startRow = max(1, round(startRow));
            endRow = round(endRow);
            if startRow >= endRow
                return;
            end
            obj.AxesData_{axesIdx}.Channels{chanIdx}.SliceRange = [startRow, endRow];
            notify(obj, 'ChannelsUpdated');
        end

        function chan = GetChannel(obj, axesIdx, chanIdx)
        % GetChannel 获取单个通道结构体
            chan = [];
            if axesIdx < 1 || axesIdx > length(obj.AxesData_) || isempty(obj.AxesData_{axesIdx})
                return;
            end
            chans = obj.AxesData_{axesIdx}.Channels;
            if chanIdx < 1 || chanIdx > length(chans)
                return;
            end
            chan = chans{chanIdx};
        end

        % ---- Axes 归一化 ----

        function SetAxesNormMode(obj, axesIdx, mode)
        % SetAxesNormMode 设置 axes 的归一化模式
            while length(obj.AxesNormMode_) < axesIdx
                obj.AxesNormMode_{end+1} = 'none'; %#ok<AGROW>
            end
            obj.AxesNormMode_{axesIdx} = mode;
        end

        function mode = GetAxesNormMode(obj, axesIdx)
        % GetAxesNormMode 获取 axes 的归一化模式
            if axesIdx >= 1 && axesIdx <= length(obj.AxesNormMode_)
                mode = obj.AxesNormMode_{axesIdx};
            else
                mode = 'none';
            end
        end

        % ---- 归一化参数 ----

        function SetAxesNormParams(obj, axesIdx, params)
        % SetAxesNormParams 设置 axes 的归一化参数
            while length(obj.AxesNormParams_) < axesIdx
                obj.AxesNormParams_{end+1} = struct(); %#ok<AGROW>
            end
            obj.AxesNormParams_{axesIdx} = params;
        end

        function params = GetAxesNormParams(obj, axesIdx)
        % GetAxesNormParams 获取 axes 的归一化参数
            if axesIdx >= 1 && axesIdx <= length(obj.AxesNormParams_)
                params = obj.AxesNormParams_{axesIdx};
            else
                params = struct();
            end
        end

        % ---- 横轴/右Y轴引用 ----

        function SetXChannel(obj, axesIdx, datasetIdx, colIdx)
        % SetXChannel 设置 axes 的横轴通道引用
            if axesIdx < 1 || axesIdx > obj.MaxAxes_
                return;
            end
            while length(obj.AxesXChannel_) < axesIdx
                obj.AxesXChannel_{end+1} = []; %#ok<AGROW>
            end
            obj.AxesXChannel_{axesIdx} = struct('DatasetIdx', datasetIdx, 'ColIdx', colIdx);
        end

        function ClearXChannel(obj, axesIdx)
        % ClearXChannel 恢复 axes 默认横轴（采样索引）
            if axesIdx >= 1 && axesIdx <= length(obj.AxesXChannel_)
                obj.AxesXChannel_{axesIdx} = [];
            end
        end

        function [datasetIdx, colIdx] = GetXChannel(obj, axesIdx)
        % GetXChannel 查询 axes 的横轴引用，无则返回空
            datasetIdx = [];
            colIdx = [];
            if axesIdx >= 1 && axesIdx <= length(obj.AxesXChannel_) && ~isempty(obj.AxesXChannel_{axesIdx})
                ref = obj.AxesXChannel_{axesIdx};
                datasetIdx = ref.DatasetIdx;
                colIdx = ref.ColIdx;
            end
        end

        function SetRightYChannel(obj, axesIdx, datasetIdx, colIdx)
        % SetRightYChannel 追加 axes 的右Y轴通道引用（支持多个）
            if axesIdx < 1 || axesIdx > obj.MaxAxes_
                return;
            end
            while length(obj.AxesRightYChannel_) < axesIdx
                obj.AxesRightYChannel_{end+1} = {}; %#ok<AGROW>
            end
            if isempty(obj.AxesRightYChannel_{axesIdx})
                obj.AxesRightYChannel_{axesIdx} = {};
            end
            % 检查重复
            refs = obj.AxesRightYChannel_{axesIdx};
            for i = 1:length(refs)
                if refs{i}.DatasetIdx == datasetIdx && refs{i}.ColIdx == colIdx
                    return; % 已存在
                end
            end
            obj.AxesRightYChannel_{axesIdx}{end+1} = struct('DatasetIdx', datasetIdx, 'ColIdx', colIdx);
        end

        function ClearRightYChannel(obj, axesIdx)
        % ClearRightYChannel 恢复 axes 单Y轴模式（清除全部右Y通道）
            if axesIdx >= 1 && axesIdx <= length(obj.AxesRightYChannel_)
                obj.AxesRightYChannel_{axesIdx} = {};
            end
        end

        function refs = GetRightYChannel(obj, axesIdx)
        % GetRightYChannel 查询 axes 的右Y轴引用列表，无则返回空 cell
            refs = {};
            if axesIdx >= 1 && axesIdx <= length(obj.AxesRightYChannel_) && ~isempty(obj.AxesRightYChannel_{axesIdx})
                refs = obj.AxesRightYChannel_{axesIdx};
            end
        end

        % ---- 路径记忆 ----

        function SetLastPath(obj, slotIndex, path)
            if slotIndex >= 1 && slotIndex <= length(obj.LastPaths_)
                obj.LastPaths_{slotIndex} = path;
            end
        end

        function path = GetLastPath(obj, slotIndex)
            if slotIndex >= 1 && slotIndex <= length(obj.LastPaths_)
                path = obj.LastPaths_{slotIndex};
            else
                path = '';
            end
        end

        % ---- Dependent ----

        function val = get.DatasetCount(obj)
            val = length(obj.Datasets_);
        end

        function val = get.AxesCount(obj)
            val = 0;
            for i = 1:length(obj.AxesData_)
                if ~isempty(obj.AxesData_{i}) && ~isempty(obj.AxesData_{i}.Channels)
                    val = val + 1;
                end
            end
        end

        function val = get.AxesSlotCount(obj)
            val = length(obj.AxesData_);
        end
    end

    methods (Access = private)
        function ensureAxesCapacity(obj, axesIdx)
        % ensureAxesCapacity 确保所有 axes 容器至少有 axesIdx 个槽位
            while length(obj.AxesData_) < axesIdx
                obj.AxesData_{end+1} = struct('Channels', {{}}); %#ok<AGROW>
            end
            while length(obj.AxesNormMode_) < axesIdx
                obj.AxesNormMode_{end+1} = 'none'; %#ok<AGROW>
            end
            while length(obj.AxesXChannel_) < axesIdx
                obj.AxesXChannel_{end+1} = []; %#ok<AGROW>
            end
            while length(obj.AxesRightYChannel_) < axesIdx
                obj.AxesRightYChannel_{end+1} = {}; %#ok<AGROW>
            end
            while length(obj.AxesNormParams_) < axesIdx
                obj.AxesNormParams_{end+1} = struct(); %#ok<AGROW>
            end
        end
    end
end
