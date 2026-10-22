% Open this file from the extracted V2 folder and press Run.
% You can keep the old ZIP and toolkit folder; this selects the new copy.
v2ToolkitFolder = fileparts(mfilename('fullpath'));
assert(isfile(fullfile(v2ToolkitFolder, 'data', 'model_v2.json')), ...
    'ufc:V2Incomplete', 'Extract the entire V2 ZIP before running this file.');
cd(v2ToolkitFolder);
addpath(v2ToolkitFolder, '-begin');
clear functions
rehash;
assert(strcmpi(which('compare_ufc'), fullfile(v2ToolkitFolder, 'compare_ufc.m')) ...
    && strcmpi(which('ufc_toolkit'), fullfile(v2ToolkitFolder, 'ufc_toolkit.m')), ...
    'ufc:V2Path', 'MATLAB is still resolving files outside the V2 folder.');
fprintf('\nUFC TOOLKIT V2 IS ACTIVE\nFolder: %s\n', v2ToolkitFolder);
fprintf('The updated model is the default. Enter the two fighter names below.\n\n');
compare_ufc
