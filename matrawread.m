function varargout = matrawread(raw_dir, varargin)
% MATRAWREAD (MATlab RAW data READ) converts raw data from DSLR/DSLM to 
% MATLAB-readable file(s). 
% Make sure dcraw.exe is accessible before running. If not, place it in
% c:\windows\ or add its path to the value of the PATH environment 
% variable. If multiple versions of dcraw.exe are accessible, modify line
% 117 to specify the version you wish to call.
%
% USAGE:
% matrawread(raw_dir, 'param', value, ...)
%   : save the converted file(s) to the disk
%
% I = matrawread(raw_dir, 'param', value, ...)
%   : load the converted image into MATLAB workspace
%
% [I, image_info] = matrawread(raw_dir, 'param', value, ...)
%   : load the converted image and raw data info into MATLAB workspace
%
% INPUTS:
% raw_dir: path of the raw data file(s). Use wildcard '*' to select all
%          files in the directory, e.g., 'c:\foo\*.NEF'
%
% OPTIONAL PARAMETERS:
% cfa: color filter array of the DSLR/DSLM. Its value can only be one of
%      'RGGB', 'BGGR', 'GRBG', 'GBRG', and 'XTrans'. (default = 'RGGB')
% darkness: specify the darkness level for the DSLR/DSLM. If unknown,
%           capture one frame with lens cap on and then evaluate it.
%           (default = 0) 
% bit: specify the valid bit depth for the raw data. All pixel values will
%      be normalized by dividing by (2^bit-1) and then stored as uint16
%      data type. (default = 14)
% format: select in which data format to store the converted file(s). Only
%         'mat', 'ppm', 'png', and 'tiff' are supported. If an image format
%         is required, 'ppm' is highly recommended. (default = 'mat')
% interpolation: can be either true or false. If true, MATLAB built-in
%                function demosaic() will be used to generate a H*W*3 color
%                image from the H*W*1 (grayscale) cfa image. Otherwise, no
%                interpolation will be performed, thus generating a 
%                (H/2)*(W/2)*3 color image (or (H/3)*(W/3)*3 for Fujifilm's
%                X-Trans CFA). Note: interpolation for X-Trans CFA will be
%                extremely slow. (default = false)
% saturation: specify the saturation level for the DSLR/DSLM. If unknown,
%             overexpose a scene by 5 or 6 stops and then evaluate it.
%             (default = 2^bit-1)
% save: specify whether to save the converted file to the disk. Only
%       alternative when an output argument is given and no wildcard (*) is
%       used in raw_dir. Otherwise, it will be forced to be true. Set this
%       to false to save time if you only wish to access the converted data
%       in MATLAB workspace. (default = false)
% info: can be either true or false. If true, output file(s) will be
%       renamed with capturing parameters (exposure time, F number, ISO,
%       time stamp). (default = false)
% keeppgm: can be either true or false. If true, the temporary .pgm file
%          generated by dcraw.exe will be kept. (default = false)
% suffix: add a suffix to the output file name(s). This will be useful if 
%         you want to convert the same raw data with different settings.
%         (default = '')
% print: print parameters. (default = false)
%
% NOTE:
% the function has only been tested on Windows with MATLAB version higher
% than R2016b and Dcraw version v9.27
%
% Copyright
% Qiu Jueqin - Jan, 2019

% parse input parameters
param = parseInput(varargin{:});

% if no output argument is specified, or a output fotmat is given, force to
% save the converted file(s) to the disk
if nargout == 0 || ~strcmpi(param.format, 'N/A')
    param.save = true;
end

% if the converted file(s) is to be saved to the disk but no output format
% is given, use .mat as default format
if param.save == true && strcmpi(param.format, 'N/A')
    param.format = 'mat';
end

% if no saturation level is specified, use (2^bit - 1) as default
if isempty(param.saturation)
    param.saturation = 2^param.bit - 1;
else
    assert(param.saturation <= 2^param.bit - 1, 'Saturation level %0.f is greater than the valid maximum value %d (2^%d-1).',...
                                                param.saturation, 2^param.bit-1, param.bit);
end

% list all raw data files
folder_contents = dir(raw_dir);

if numel(folder_contents) > 1
    param.save = true;
    param.print = true;
    disp('Processes started. Do not modify the temporary .pgm files before the processes completed.');
    if nargout > 0
        warning('To load image into workspace, use a specified file name instead of a wildcard (*).');
    end
elseif numel(folder_contents) == 0
    error('File %s is not found. Make sure the path is accessible by MATLAB, or consider to use absolute path.', raw_dir);
end

if param.print == true
    printParams(param);
end

for i = 1:numel(folder_contents)
    if numel(folder_contents) > 1
        fprintf('Processing %s... (%d/%d)\n', folder_contents(i).name, i, numel(folder_contents));
    end
    raw_file = fullfile(folder_contents(i).folder, folder_contents(i).name);
    [folder, name, extension] = fileparts(raw_file);
    
    % call dcraw.exe in cmd and convert raw data to a .pgm file, without
    % any further processing
    [status, cmdout] = system(['dcraw -4 -D ', raw_file]); % save to .pgm file(s)
    if status
        error(cmdout);
    end
    
    pgm_file = strrep(raw_file, extension, '.pgm');
    % read image from the .pgm file
    raw = imread(pgm_file);

    % delete the .pgm file
    if param.keeppgm == false
        delete(pgm_file);
    end
    
    % subtract the darkness level
    raw = raw - param.darkness;
    
    % demosaicking
    if param.interpolation == true
        raw = demosaic_(raw, param.cfa);
    else
        raw = demosaic_nointerp(raw, param.cfa);
    end
    
    % normalize the image and convert it to uint16
    raw = uint16( double(raw) / (param.saturation - param.darkness) * (2^16 - 1) );
    
    if param.save == true
        % extract capturing parameters and rename the file
        if param.info == true
            try
                info = imfinfo(raw_file);
                if numel(info) > 1
                    info = info(1);
                end
                exposure = info.DigitalCamera.ExposureTime;
                f_number = info.DigitalCamera.FNumber;
                iso = info.DigitalCamera.ISOSpeedRatings;
                datatime = info.DigitalCamera.DateTimeDigitized;
                datatime = strrep(datatime,':','');
                datatime = strrep(datatime,' ','_');
                name = strjoin({name,...
                                sprintf('EXP%.0f', 1000*exposure),... % shutter speed in millisecond
                                sprintf('F%.1f', f_number),...
                                sprintf('ISO%d', iso),...
                                datatime}, '_');
            catch
                warning('Can not extract capturing info.');
            end
        end

        % add suffix
        if ~isempty(param.suffix)
            name = strjoin({name, param.suffix}, '_');
        end

        % save the image in user-specified format
        name = strjoin({name, param.format}, '.');
        save_dir = fullfile(folder, name);
        if strcmpi(param.format, 'mat')
            save(save_dir, 'raw', '-v7.3');
        elseif strcmpi(param.format, 'ppm')
            imwrite(raw, save_dir);
        elseif strcmpi(param.format, 'tiff')
            imwrite(raw, save_dir, 'compression', 'none');
        elseif strcmpi(param.format, 'png')
            imwrite(raw, save_dir, 'bitdepth', 16);
        end
    end
    
end

if nargout > 0
    varargout{1} = raw;
end
if nargout > 1
    info = imfinfo(raw_file);
    if numel(info) > 1
        info = info(1);
    end
    varargout{2} = info;
end

if numel(folder_contents) > 1
    disp('Done.');
end

end


function RGB = demosaic_(raw, sensorAlignment)
% a wrapper for built-in demosaic funtion    
assert(isa(raw, 'uint16'));
if strcmpi(sensorAlignment, 'XTrans')
    disp('Interpolation for X-Trans CFA will be slow. Keep your patience...');
    RGB = uint16(demosaic_xtrans(double(raw)));
else
    RGB = demosaic(raw, sensorAlignment);
end
end

        
function RGB = demosaic_nointerp(raw, sensorAlignment)
% DEMOSAIC_NOINTERP performs demosaicking without interpolation
% 
% MATLAB built-in demosaic function generates a H*W*3 color image from a
% H*W*1 grayscale cfa image by 'guessing' the pixel's RGB values from its
% neighbors, which might introduces some color biases (althout negligible
% for most of applications).
%
% DEMOSAIC_NOINTERP generates a (H/2)*(W/2)*3 color image from the original
% cfa image without interpolation. The G value of each pixel in the output
% color image is produced by averaging two green sensor elements in the
% quadruplet.

if strcmpi(sensorAlignment, 'XTrans')
    RGB = demosaic_xtrans_nointerp(raw);
else
    [height, width] = size(raw);
    if mod(height, 2) ~= 0
        raw = raw(1:end-1, :);
    end
    if mod(width, 2) ~= 0
        raw = raw(:, 1:end-1);
    end

    switch upper(sensorAlignment)
        case 'RGGB'
            [r_begin, g1_begin, g2_begin, b_begin] = deal([1, 1], [1, 2], [2, 1], [2, 2]);
        case 'BGGR'
            [r_begin, g1_begin, g2_begin, b_begin] = deal([2, 2], [1, 2], [2, 1], [1, 1]);
        case 'GBRG'
            [r_begin, g1_begin, g2_begin, b_begin] = deal([2, 1], [1, 1], [2, 2], [1, 2]);
        case 'GRBG'
            [r_begin, g1_begin, g2_begin, b_begin] = deal([1, 2], [1, 1], [2, 2], [2, 1]);
    end
    R = raw(r_begin(1):2:end, r_begin(2):2:end);
    G1 = raw(g1_begin(1):2:end, g1_begin(2):2:end);
    G2 = raw(g2_begin(1):2:end, g2_begin(2):2:end);
    B = raw(b_begin(1):2:end, b_begin(2):2:end);
    RGB  = cat(3, R, (G1 + G2)/2, B);
end
end


function param = parseInput(varargin)
% Parse inputs & return structure of parameters

parser = inputParser;
parser.addParameter('cfa', 'RGGB', @(x)any(strcmpi(x, {'RGGB', 'BGGR', 'GBRG', 'GRBG', 'XTrans'})));
parser.addParameter('bit', 14, @(x)validateattributes(x, {'numeric'}, {'integer', 'nonnegative'}));
parser.addParameter('darkness', 0, @(x)validateattributes(x, {'numeric'}, {'nonnegative'}));
parser.addParameter('format', 'N/A', @(x)any(strcmpi(x, {'N/A', 'mat', 'ppm', 'png', 'tiff'})));
parser.addParameter('info', false, @(x)islogical(x));
parser.addParameter('interpolation', false, @(x)islogical(x));
parser.addParameter('keeppgm', false, @(x)islogical(x));
parser.addParameter('print', false, @(x)islogical(x));
parser.addParameter('saturation', [], @(x)validateattributes(x, {'numeric'}, {'nonnegative'}));
parser.addParameter('save', false, @(x)islogical(x));
parser.addParameter('suffix', '', @(x)ischar(x));
parser.parse(varargin{:});
param = parser.Results;
end


function printParams(param)
if strcmpi(param.cfa, 'XTrans') % make format pretty
    param.cfa = 'X-Trans';
else
    param.cfa = upper(param.cfa);
end
disp('Conversion parameters:')
disp('==============================================================================');
field_names = fieldnames(param);
field_name_dict.cfa = 'Color filter array';
field_name_dict.bit = 'Bit depth';
field_name_dict.darkness = 'Darkness level';
field_name_dict.format = 'Output format';
field_name_dict.info = 'Rename with capturing info';
field_name_dict.interpolation = 'Demosaicking with interpolation';
field_name_dict.keeppgm = 'Keep the temporary .pgm files';
field_name_dict.saturation = 'Saturation level';
field_name_dict.save = 'Save outputs to the disk';
field_name_dict.suffix = 'Filename suffix';
for i = 1:numel(field_names)
    if ~strcmpi(field_names{i}, 'print')
        len = fprintf('%s:',field_name_dict.(field_names{i}));
        fprintf(repmat(' ', 1, 40-len));
        fprintf('%s\n', string(param.(field_names{i})));
    end
end
disp('==============================================================================');
end