classdef EventCapture < handle
%EVENTCAPTURE  Handle-class event accumulator for unittest listeners.
%   Because nested-function closures in helper methods produce value-copies,
%   a handle class is needed so the listener callback and the test method
%   share the same mutable container.
%
%   Usage:
%     cap = EventCapture();
%     lh  = addlistener(obj, 'MyEvent', @(~,e) cap.store(e));
%     ... trigger ...
%     assert(~isempty(cap.Events));
%     delete(lh);

    properties
        Events cell = {}
    end

    methods
        function store(obj, e)
        %STORE  Append event payload to the accumulator.
        %   Handles both AppEventData (with .Data) and plain event.EventData.
            if isempty(e)
                obj.Events{end+1} = struct();
            elseif isprop(e, 'Data')
                obj.Events{end+1} = e.Data;
            else
                obj.Events{end+1} = struct();
            end
        end
    end
end
