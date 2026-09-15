classdef FileExplorer
% FileExplorer - 文件/路径工具
%
% 纯函数集合。所有方法 Static。

    methods (Static)
        function files = ListByExtension(rootDir, extensions)
        % ListByExtension 递归列出指定扩展名的文件（BFS）
        %
        % 输入：
        %   rootDir    - char 根目录
        %   extensions - cell 扩展名列表，如 {'.dat', '.txt', '.csv'}
        %
        % 输出：
        %   files - cell {1×N} 完整文件路径列表

            validateattributes(rootDir, {'char'}, {'nonempty'});
            validateattributes(extensions, {'cell'}, {'nonempty'});

            % 确保扩展名都以 . 开头且为小写
            for i = 1:length(extensions)
                ext = extensions{i};
                if ext(1) ~= '.'
                    ext = ['.' ext];
                end
                extensions{i} = lower(ext);
            end

            files = {};
            queue = {rootDir};

            while ~isempty(queue)
                currentDir = queue{1};
                queue(1) = [];

                listing = dir(currentDir);
                for i = 1:length(listing)
                    item = listing(i);
                    if item.isdir
                        if ~strcmp(item.name, '.') && ~strcmp(item.name, '..')
                            queue{end+1} = fullfile(currentDir, item.name); %#ok<AGROW>
                        end
                    else
                        [~, ~, ext] = fileparts(item.name);
                        if any(strcmpi(ext, extensions))
                            files{end+1} = fullfile(currentDir, item.name); %#ok<AGROW>
                        end
                    end
                end
            end
        end

        function parentDir = GetParentDir(filePath)
        % GetParentDir 获取父目录
            parentDir = fileparts(filePath);
        end

        function dirPath = EnsureTrailingSep(dirPath)
        % EnsureTrailingSep 确保路径有尾部分隔符
            if dirPath(end) ~= filesep
                dirPath = [dirPath filesep];
            end
        end

        function info = GetFileInfo(filePath)
        % GetFileInfo 获取文件信息
        %
        % 输出：
        %   info.bytes     - double 文件大小
        %   info.datenum   - double 修改时间
        %   info.extension - char 扩展名

            d = dir(filePath);
            if isempty(d)
                error('SignalAnalysis:FileExplorer:FileNotFound', ...
                    'File not found: %s', filePath);
            end
            [~, ~, ext] = fileparts(filePath);
            info = struct('bytes', d.bytes, 'datenum', d.datenum, 'extension', lower(ext));
        end
    end
end
