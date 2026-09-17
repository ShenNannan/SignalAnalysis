classdef DataPreparationService
%DATAPREPARATIONSERVICE  Pure static algorithms for plot-data preparation.
%   Stateless, UI-free. All methods are Static and can be unit-tested
%   directly from the command window.
%
%   Extracted from the old TimeSeriesPresenter to enforce L4/L3 separation:
%   the Presenter calls these functions, the View never does.

    methods (Static)
        % ================================================================
        %  Core: channel → aligned plot vectors
        % ================================================================

        function [xPlot, yPlot] = PreparePlotData(data, xRaw, sliceRange, hasXChannel, normMode, normStats)
        %PREPAREPLOTDATA  Slice, align, and normalize a single channel.
        %
        %   [xPlot, yPlot] = DataPreparationService.PreparePlotData( ...
        %       data, xRaw, sliceRange, hasXChannel, normMode, normStats)
        %
        %   Inputs:
        %     data        - [N×1] raw signal
        %     xRaw        - [M×1] custom X-axis data (ignored if ~hasXChannel)
        %     sliceRange  - [start, end] or [] (no slice)
        %     hasXChannel - logical, true if using a custom X channel
        %     normMode    - 'none'|'minmax'|'zscore'|'meanzero'
        %     normStats   - struct(minY, maxY, meanY, stdY) or []
        %
        %   Outputs:
        %     xPlot - [K×1] aligned X vector
        %     yPlot - [K×1] aligned (and optionally normalized) Y vector

            arguments
                data        (:,1) double
                xRaw        (:,1) double = double.empty(0,1)
                sliceRange  (1,:) double = double.empty(1,0)
                hasXChannel (1,1) logical = false
                normMode    (1,1) string  = "none"
                normStats   (1,1) struct  = struct()
            end

            % Step 1: slice and align
            [yPlot, xPlot] = ChannelOperations.SliceAndAlign( ...
                data, xRaw, sliceRange, hasXChannel);

            % Step 2: normalize
            if ~strcmpi(normMode, "none") && ~isempty(fieldnames(normStats))
                yPlot = ChannelOperations.ApplyNorm(yPlot, normMode, normStats);
            end
        end

        % ================================================================
        %  Batch: multiple channels → cell arrays for RenderWaveform
        % ================================================================

        function [xCell, yCell, labels, colors] = PrepareMultiChannel(channels, xRaw, hasXChannel, normMode, normParamsMap, nColors)
        %PREPAREMULTICHANNEL  Prepare all left-Y channels in one call.
        %
        %   [xCell, yCell, labels, colors] = DataPreparationService.PrepareMultiChannel( ...
        %       channels, xRaw, hasXChannel, normMode, normParamsMap, nColors)
        %
        %   Inputs:
        %     channels      - cell of channel structs (from Session)
        %     xRaw          - [M×1] custom X data, or []
        %     hasXChannel   - logical
        %     normMode      - 'none'|'minmax'|'zscore'|'meanzero'
        %     normParamsMap - struct with .channelStats cell array (indexed
        %                     by channel order), or []
        %     nColors       - total color palette size
        %
        %   Outputs:
        %     xCell   - cell of [K×1] X vectors
        %     yCell   - cell of [K×1] Y vectors
        %     labels  - cell of char (display names)
        %     colors  - cell of [1×3] RGB vectors

            xCell   = {};
            yCell   = {};
            labels  = {};
            colors  = {};

            for c = 1:numel(channels)
                chan = channels{c};

                % Normalize stats (indexed by channel order in the axes)
                stats = struct();
                if ~strcmpi(normMode, "none") ...
                        && isstruct(normParamsMap) ...
                        && isfield(normParamsMap, 'channelStats') ...
                        && c <= numel(normParamsMap.channelStats)
                    stats = normParamsMap.channelStats{c};
                end

                [xp, yp] = DataPreparationService.PreparePlotData( ...
                    chan.Data, xRaw, chan.SliceRange, hasXChannel, ...
                    normMode, stats);

                xCell{end+1}  = xp;   %#ok<AGROW>
                yCell{end+1}  = yp;   %#ok<AGROW>
                labels{end+1} = chan.Label; %#ok<AGROW>
                colors{end+1} = DataPreparationService.ChannelColor( ...
                    chan.DatasetIdx, chan.ColIdx, nColors); %#ok<AGROW>
            end
        end

        % ================================================================
        %  X-data construction (for cursor addressing)
        % ================================================================

        function xData = BuildXData(firstChannel, xRaw, hasXChannel)
        %BUILDXDATA  Build the X-axis vector for cursor snapping.
        %   Uses the first channel's slice range as reference.
        %
        %   xData = DataPreparationService.BuildXData(firstChannel, xRaw, hasXChannel)
        %
        %   firstChannel - the first channel struct in this axes (or [])

            if isempty(firstChannel)
                xData = [];
                return
            end

            sr = [];
            if isfield(firstChannel, 'SliceRange')
                sr = firstChannel.SliceRange;
            end

            if ~isempty(sr)
                if hasXChannel
                    xData = ChannelOperations.ApplySlice(xRaw, sr(1), sr(2));
                else
                    n = sr(2) - sr(1) + 1;
                    xData = (0:n-1)';
                end
            else
                if hasXChannel
                    n = min(length(xRaw), length(firstChannel.Data));
                    xData = xRaw(1:n);
                else
                    xData = (0:length(firstChannel.Data)-1)';
                end
            end
        end

        % ================================================================
        %  Cursor readout helpers
        % ================================================================

        function [rawIdx, yVal] = ReadChannelAtCursor(chanData, sliceRange, xDataIdx, hasXChannel)
        %READCHANNELATCURSOR  Map a cursor xDataIdx back to raw data.
        %
        %   [rawIdx, yVal] = DataPreparationService.ReadChannelAtCursor( ...
        %       chanData, sliceRange, xDataIdx, hasXChannel)
        %
        %   Inputs:
        %     chanData     - [N×1] raw signal
        %     sliceRange   - [start, end] or []
        %     xDataIdx     - 1-based index into the sliced/aligned data
        %     hasXChannel  - logical
        %
        %   Outputs:
        %     rawIdx - 1-based index into the original raw data
        %     yVal   - chanData(rawIdx), or NaN if out of bounds

            if hasXChannel
                rawIdx = xDataIdx;
            else
                offset = 0;
                if ~isempty(sliceRange)
                    offset = sliceRange(1) - 1;
                end
                rawIdx = xDataIdx + offset;
            end

            if rawIdx >= 1 && rawIdx <= length(chanData)
                yVal = chanData(rawIdx);
            else
                yVal = NaN;
            end
        end

        % ================================================================
        %  Color and label utilities
        % ================================================================

        function rgb = ChannelColor(datasetIdx, colIdx, nColors)
        %CHANNELCOLOR  Hash-based color index (order-independent).
        %
        %   rgb = DataPreparationService.ChannelColor(datasetIdx, colIdx, nColors)
        %   Returns a [1×3] RGB vector from the default MATLAB color order.

            idx = mod((datasetIdx - 1) * 7 + colIdx, nColors) + 1;
            cmap = lines(nColors);
            rgb  = cmap(idx, :);
        end

        function idx = ChannelColorIndex(datasetIdx, colIdx, nColors)
        %CHANNELCOLORINDEX  Hash-based color index (1-based integer).
        %
        %   idx = DataPreparationService.ChannelColorIndex(datasetIdx, colIdx, nColors)

            idx = mod((datasetIdx - 1) * 7 + colIdx, nColors) + 1;
        end

        function name = ShortLabel(label)
        %SHORTLABEL  Extract display name after first '/'.
        %
        %   name = DataPreparationService.ShortLabel('/ch1_pos')
        %   returns 'ch1_pos'

            [~, short] = strtok(label, '/');
            if isempty(short)
                name = label;
            else
                name = strtrim(short(2:end));
            end
        end

        function chan = FindChannel(channels, datasetIdx, colIdx)
        %FINDCHANNEL  Locate a channel in a cell array by (datasetIdx, colIdx).
        %
        %   chan = DataPreparationService.FindChannel(channels, datasetIdx, colIdx)
        %   Returns [] if not found.

            chan = [];
            for i = 1:numel(channels)
                c = channels{i};
                if c.DatasetIdx == datasetIdx && c.ColIdx == colIdx
                    chan = c;
                    return
                end
            end
        end

        % ================================================================
        %  Slice-tag label (for channel table display)
        % ================================================================

        function tag = BuildSliceTag(sliceRange, totalRows)
        %BUILDSLICETAG  Build "[start~end Llen]" suffix if sliced.
        %
        %   tag = DataPreparationService.BuildSliceTag(sliceRange, totalRows)
        %   Returns '' if no slice or full range.

            tag = '';
            if isempty(sliceRange), return; end

            sr     = sliceRange;
            segLen = sr(2) - sr(1) + 1;

            if sr(1) > 1 || sr(2) < totalRows || sr(2) > totalRows
                tag = sprintf(' [%d~%d L%d]', sr(1), sr(2), segLen);
            end
        end
    end
end
