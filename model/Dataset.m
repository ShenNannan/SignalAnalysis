classdef Dataset < handle
% Dataset - 统一数据容器（handle + immutable 引用语义）
%
% 所有 DataReaderFactory.LoadStandard 输出此类型。
% 下游代码（Presenter, SignalProcessor）只通过此接口访问数据。
%
% 设计原则：
%   - L0（矩阵）必需
%   - L1（采样率）有默认值（1Hz），用户可覆盖
%   - L2（列名）自动生成，用户可覆盖
%   - Units/Descriptions 私有，通过 GetDisplayLabel 智能组合
%
% 注意：handle 类 + SetAccess = immutable = 引用语义但不可原地修改。
% 需要"修改"属性时（如更新采样率、列名），使用 RebuildWith* 方法
% 创建新实例，再通过 Session.UpdateDataset 替换。

    properties (SetAccess = immutable)
        Values          double   % [N×M] 数值矩阵
        ColumnNames     cell     % {1×M} 列名
        SampleRate      double   % 采样率 Hz
        SourcePath      char     % 来源文件路径
        FormatTag       char     % 格式标识
        Metadata        struct   % 扩展元数据
    end

    properties (Access = private)
        Units_          cell     % {1×M} 每列单位
        Descriptions_   cell     % {1×M} 每列描述
    end

    properties (Dependent)
        SampleTime      double   % 1/SampleRate
        RowCount        double   % 行数
        ColumnCount     double   % 列数
        TimeVector      double   % [N×1] 时间轴
        Duration        double   % 总时长
    end

    methods
        function obj = Dataset(values, colNames, sampleRate, sourcePath, formatTag, metadata, units, descriptions)
        % Dataset 构造函数
        %
        % 输入：
        %   values      - [N×M double] 必需
        %   colNames    - {1×M cell} 或 []（自动生成 Channel_N）
        %   sampleRate  - double 或 []（默认 1Hz）
        %   sourcePath  - char 或 ''
        %   formatTag   - char 或 ''
        %   metadata    - struct 或 struct()
        %   units       - {1×M cell} 或 {}
        %   descriptions- {1×M cell} 或 {}

            % L0: 矩阵（必需）
            validateattributes(values, {'numeric'}, {'2d', 'nonempty'});
            obj.Values = double(values);

            [nRows, nCols] = size(values); %#ok<ASGU>

            % L2: 列名（可选，自动生成）
            if isempty(colNames)
                obj.ColumnNames = arrayfun(@(i) sprintf('Channel_%d', i), ...
                    1:nCols, 'UniformOutput', false);
            else
                if length(colNames) ~= nCols
                    error('SignalAnalysis:Dataset:InvalidColumnNames', ...
                        'ColumnNames count (%d) must match number of columns (%d)', ...
                        length(colNames), nCols);
                end
                obj.ColumnNames = colNames;
            end

            % L1: 采样率（可选，空表示未设置）
            if isempty(sampleRate)
                obj.SampleRate = [];
            else
                validateattributes(sampleRate, {'numeric'}, {'positive', 'scalar'});
                obj.SampleRate = sampleRate;
            end

            % 可选参数
            if nargin < 4 || isempty(sourcePath), sourcePath = ''; end
            if nargin < 5 || isempty(formatTag), formatTag = ''; end
            if nargin < 6 || isempty(metadata), metadata = struct(); end
            if nargin < 7 || isempty(units), units = cell(1, nCols); end
            if nargin < 8 || isempty(descriptions), descriptions = cell(1, nCols); end

            obj.SourcePath = sourcePath;
            obj.FormatTag = formatTag;
            obj.Metadata = metadata;
            obj.Units_ = units;
            obj.Descriptions_ = descriptions;
        end

        function col = GetColumn(obj, index)
        % GetColumn 获取指定列的数据向量
            if index < 1 || index > obj.ColumnCount
                error('SignalAnalysis:Dataset:IndexOutOfBounds', ...
                    'Column index %d out of range [1, %d]', index, obj.ColumnCount);
            end
            col = obj.Values(:, index);
        end

        function name = GetColumnName(obj, index)
        % GetColumnName 获取指定列的名称
            name = obj.ColumnNames{index};
        end

        function unit = GetUnit(obj, index)
        % GetUnit 获取指定列的单位，缺失返回 ''
            if index <= length(obj.Units_)
                unit = obj.Units_{index};
            else
                unit = '';
            end
        end

        function desc = GetDescription(obj, index)
        % GetDescription 获取指定列的描述，缺失返回 ''
            if index <= length(obj.Descriptions_)
                desc = obj.Descriptions_{index};
            else
                desc = '';
            end
        end

        function label = GetDisplayLabel(obj, colIdx)
        % GetDisplayLabel 智能组合显示标签
        %   有描述有单位 → '描述 (单位)'
        %   无描述有单位 → '列名 (单位)'
        %   有描述无单位 → '描述'
        %   都无 → '列名'
            desc = obj.GetDescription(colIdx);
            unit = obj.GetUnit(colIdx);
            name = obj.ColumnNames{colIdx};

            if ~isempty(desc) && ~isempty(unit)
                label = sprintf('%s (%s)', desc, unit);
            elseif ~isempty(unit)
                label = sprintf('%s (%s)', name, unit);
            elseif ~isempty(desc)
                label = desc;
            else
                label = name;
            end
        end

        function sub = GetColumnRange(obj, colIndices)
        % GetColumnRange 获取指定列范围的子数据集
            sub = Dataset(obj.Values(:, colIndices), ...
                obj.ColumnNames(colIndices), ...
                obj.SampleRate, obj.SourcePath, obj.FormatTag, obj.Metadata, ...
                obj.Units_(colIndices), obj.Descriptions_(colIndices));
        end

        function sub = GetRowRange(obj, startRow, endRow)
        % GetRowRange 获取指定行范围的子数据集
            sub = Dataset(obj.Values(startRow:endRow, :), ...
                obj.ColumnNames, obj.SampleRate, ...
                obj.SourcePath, obj.FormatTag, obj.Metadata, ...
                obj.Units_, obj.Descriptions_);
        end

        function ds = RebuildWithSampleRate(obj, newRate)
        % RebuildWithSampleRate 用新采样率重建 Dataset
            ds = Dataset(obj.Values, obj.ColumnNames, newRate, ...
                obj.SourcePath, obj.FormatTag, obj.Metadata, ...
                obj.Units_, obj.Descriptions_);
        end

        function ds = RebuildWithColumnNames(obj, newNames)
        % RebuildWithColumnNames 用新列名重建 Dataset
            ds = Dataset(obj.Values, newNames, obj.SampleRate, ...
                obj.SourcePath, obj.FormatTag, obj.Metadata, ...
                obj.Units_, obj.Descriptions_);
        end

        % Dependent properties
        function ts = get.SampleTime(obj)
            if isempty(obj.SampleRate)
                ts = [];
            else
                ts = 1 / obj.SampleRate;
            end
        end

        function n = get.RowCount(obj)
            n = size(obj.Values, 1);
        end

        function n = get.ColumnCount(obj)
            n = size(obj.Values, 2);
        end

        function t = get.TimeVector(obj)
            if isempty(obj.SampleTime)
                t = [];
            else
                t = (0:obj.RowCount-1)' * obj.SampleTime;
            end
        end

        function d = get.Duration(obj)
            if isempty(obj.SampleTime)
                d = [];
            else
                d = obj.RowCount * obj.SampleTime;
            end
        end
    end
end
