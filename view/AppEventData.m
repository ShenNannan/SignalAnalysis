classdef AppEventData < event.EventData
% AppEventData 通用事件数据包装器（兼容 MATLAB R2025b notify 签名）
    properties (SetAccess = private)
        Data struct
    end
    methods
        function obj = AppEventData(data)
            obj.Data = data;
        end
    end
end
