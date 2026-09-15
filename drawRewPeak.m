function [coords, info] = drawRewPeak(varargin)
% drawRewPeak
% Sample a free Gaussian reward peak in normalized [0,1] coordinates.
%
% Usage:
%   coords = drawRewPeak(max_peak_dist_deg)
%   coords = drawRewPeak(min_peak_dist_deg, max_peak_dist_deg)
%   coords = drawRewPeak(ex)
%   coords = drawRewPeak(max_peak_dist_deg, ex)
%   coords = drawRewPeak(min_peak_dist_deg, max_peak_dist_deg, ex)
%   coords = drawRewPeak(max_peak_dist_deg, gauss_dim, ppd)
%   coords = drawRewPeak(min_peak_dist_deg, max_peak_dist_deg, gauss_dim, ppd)
%
% coords is [x y], where [0.5 0.5] is the image center.

[min_peak_dist_deg, max_peak_dist_deg, ex_or_gauss_dim, ppd] = parseInputsLocal(varargin{:});

min_peak_dist_deg = double(min_peak_dist_deg);
max_peak_dist_deg = double(max_peak_dist_deg);
if ~isscalar(min_peak_dist_deg) || ~isfinite(min_peak_dist_deg) || min_peak_dist_deg < 0
    error('drawRewPeak:BadMinPeakDistDeg', ...
        'min_peak_dist_deg must be a finite nonnegative scalar.');
end
if ~isscalar(max_peak_dist_deg) || ~isfinite(max_peak_dist_deg) || max_peak_dist_deg < 0
    error('drawRewPeak:BadMaxPeakDistDeg', ...
        'max_peak_dist_deg must be a finite nonnegative scalar.');
end
if min_peak_dist_deg > max_peak_dist_deg
    error('drawRewPeak:BadPeakDistRange', ...
        'min_peak_dist_deg must be less than or equal to max_peak_dist_deg.');
end

if isstruct(ex_or_gauss_dim)
    [gauss_dim, ppd] = resolveGeometryFromExLocal(ex_or_gauss_dim);
else
    gauss_dim = double(ex_or_gauss_dim);
end

if ~isfinite(gauss_dim) || gauss_dim <= 1
    error('drawRewPeak:BadGaussDim', ...
        'gauss_dim must be a finite scalar greater than 1.');
end
if ~isfinite(ppd) || ppd <= 0
    error('drawRewPeak:BadPpd', ...
        'ppd must be finite and positive, or pass an ex struct with setup geometry.');
end

min_radius_norm = min_peak_dist_deg * ppd / (gauss_dim - 1);
max_radius_norm = max_peak_dist_deg * ppd / (gauss_dim - 1);
coords = sampleCoordsInNormalizedAnnulusLocal(min_radius_norm, max_radius_norm);

info = struct();
info.min_peak_dist_deg = min_peak_dist_deg;
info.max_peak_dist_deg = max_peak_dist_deg;
info.min_peak_dist_norm = min_radius_norm;
info.max_peak_dist_norm = max_radius_norm;
info.gauss_dim = gauss_dim;
info.ppd = ppd;
info.distance_norm = norm(coords - [0.5, 0.5]);
info.distance_deg = info.distance_norm * (gauss_dim - 1) / ppd;
end


function [min_peak_dist_deg, max_peak_dist_deg, ex_or_gauss_dim, ppd] = parseInputsLocal(varargin)
if nargin < 1
    error('drawRewPeak:MissingInput', ...
        'Pass max_peak_dist_deg, ex, or peak distance bounds plus geometry.');
end
narginchk(1, 4);

if nargin == 1 && isstruct(varargin{1})
    ex_or_gauss_dim = varargin{1};
    min_peak_dist_deg = resolveMinPeakDistDegFromExLocal(ex_or_gauss_dim);
    max_peak_dist_deg = resolveMaxPeakDistDegFromExLocal(ex_or_gauss_dim);
    ppd = NaN;
elseif nargin == 1
    min_peak_dist_deg = 0;
    max_peak_dist_deg = varargin{1};
    ex_or_gauss_dim = defaultGeometryLocal();
    ppd = NaN;
elseif nargin == 2 && isstruct(varargin{2})
    min_peak_dist_deg = 0;
    max_peak_dist_deg = varargin{1};
    ex_or_gauss_dim = varargin{2};
    ppd = NaN;
elseif nargin == 2
    min_peak_dist_deg = varargin{1};
    max_peak_dist_deg = varargin{2};
    ex_or_gauss_dim = defaultGeometryLocal();
    ppd = NaN;
elseif nargin == 3 && isstruct(varargin{3})
    min_peak_dist_deg = varargin{1};
    max_peak_dist_deg = varargin{2};
    ex_or_gauss_dim = varargin{3};
    ppd = NaN;
elseif nargin == 3
    min_peak_dist_deg = 0;
    max_peak_dist_deg = varargin{1};
    ex_or_gauss_dim = varargin{2};
    ppd = varargin{3};
else
    min_peak_dist_deg = varargin{1};
    max_peak_dist_deg = varargin{2};
    ex_or_gauss_dim = varargin{3};
    ppd = varargin{4};
end
end


function ex = defaultGeometryLocal()
ex = struct();
ex.setup.screenRect = [0 0 1920 1080];
ex.setup.monitorWidth = 47;
ex.setup.viewingDistance = 58;
ex.exp.CoPs.graph.texture_dims = [320 320];
ex.exp.CoPs.graph.size_mult = 1080 / 320;
end


function min_peak_dist_deg = resolveMinPeakDistDegFromExLocal(ex)
min_peak_dist_deg = 0;
if isfield(ex, 'exp') && isfield(ex.exp, 'CoPs') && isfield(ex.exp.CoPs, 'ctr') && ...
        isfield(ex.exp.CoPs.ctr, 'min_peak_dist_deg') && ~isempty(ex.exp.CoPs.ctr.min_peak_dist_deg)
    min_peak_dist_deg = ex.exp.CoPs.ctr.min_peak_dist_deg;
end
end


function max_peak_dist_deg = resolveMaxPeakDistDegFromExLocal(ex)
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'ctr') || ...
        ~isfield(ex.exp.CoPs.ctr, 'max_peak_dist_deg') || isempty(ex.exp.CoPs.ctr.max_peak_dist_deg)
    error('drawRewPeak:MissingMaxPeakDistDeg', ...
        'ex.exp.CoPs.ctr.max_peak_dist_deg is required when calling with only ex.');
end
max_peak_dist_deg = ex.exp.CoPs.ctr.max_peak_dist_deg;
end


function [gauss_dim, ppd] = resolveGeometryFromExLocal(ex)
if ~isfield(ex, 'setup') || ~isfield(ex.setup, 'screenRect') || ...
        ~isfield(ex.setup, 'monitorWidth') || ~isfield(ex.setup, 'viewingDistance')
    error('drawRewPeak:MissingSetup', ...
        'ex must contain setup.screenRect, setup.monitorWidth, and setup.viewingDistance.');
end
if ~isfield(ex, 'exp') || ~isfield(ex.exp, 'CoPs') || ~isfield(ex.exp.CoPs, 'graph')
    error('drawRewPeak:MissingGraph', ...
        'ex must contain exp.CoPs.graph.');
end

graph = ex.exp.CoPs.graph;
if ~isfield(graph, 'texture_dims') || isempty(graph.texture_dims) || ...
        ~isfield(graph, 'size_mult') || isempty(graph.size_mult)
    error('drawRewPeak:MissingTextureGeometry', ...
        'ex.exp.CoPs.graph must contain texture_dims and size_mult.');
end

gauss_dim = double(graph.texture_dims(1)) * double(graph.size_mult);
screenRect = double(ex.setup.screenRect);
screenWidthPx = screenRect(3);
dpp = atan((double(ex.setup.monitorWidth) / 2) / double(ex.setup.viewingDistance)) * ...
    180 / pi / (screenWidthPx / 2);
ppd = 1 / dpp;
end


function coords = sampleCoordsInNormalizedAnnulusLocal(min_radius_norm, max_radius_norm)
center_origin = [0.5, 0.5];
max_possible_radius_norm = norm(center_origin);
if ~isfinite(min_radius_norm) || ~isfinite(max_radius_norm) || ...
        min_radius_norm < 0 || max_radius_norm < min_radius_norm
    error('drawRewPeak:BadPeakDistRangeNorm', ...
        'Normalized peak distance bounds are invalid.');
end
if min_radius_norm > max_possible_radius_norm
    error('drawRewPeak:NoFeasiblePeakDistance', ...
        'min_peak_dist_deg is too large for the normalized [0,1] image bounds.');
end
if max_radius_norm <= 0
    coords = center_origin;
    return
end

coords = center_origin;
for attempt = 1:10000 %#ok<NASGU>
    candidate = rand(1, 2);
    candidate_radius = norm(candidate - center_origin);
    if candidate_radius >= min_radius_norm && candidate_radius <= max_radius_norm
        coords = candidate;
        return
    end
end

for attempt = 1:10000 %#ok<NASGU>
    theta = rand * 2 * pi;
    if max_radius_norm == min_radius_norm
        candidate_radius = min_radius_norm;
    else
        candidate_radius = sqrt(rand * (max_radius_norm ^ 2 - min_radius_norm ^ 2) + ...
            min_radius_norm ^ 2);
    end
    candidate = center_origin + candidate_radius * [cos(theta), sin(theta)];
    if all(candidate >= 0) && all(candidate <= 1)
        coords = candidate;
        return
    end
end

error('drawRewPeak:NoSampledPeakDistance', ...
    'Could not sample a reward peak inside the requested distance bounds.');
end
