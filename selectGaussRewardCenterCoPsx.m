function [rew, selected_center_norm, center_px] = selectGaussRewardCenterCoPsx(rew, gauss_dim, max_peak_dist_norm)
% selectGaussRewardCenterCoPsx
% Resolve CoPs Gaussian reward center based on configured mode and options.
%
% Inputs:
%   rew       - ex.exp.CoPs.rew struct
%   gauss_dim           - reward matrix dimension in pixels
%   max_peak_dist_norm  - max center eccentricity in normalized map units
%
% Outputs:
%   rew                  - updated rew struct (resolved center fields)
%   selected_center_norm - [x y] center in normalized [0..1] coordinates
%   center_px            - [x y] center in reward-matrix pixel coordinates

if ~isfield(rew, 'gauss_center_positions_norm') || isempty(rew.gauss_center_positions_norm)
    rew.gauss_center_positions_norm = [0.5 0.5]; % fallback: center only
end
if nargin < 3 || isempty(max_peak_dist_norm)
    max_peak_dist_norm = defaultGaussCenterRadiusNormLocal(rew.gauss_center_positions_norm);
else
    max_peak_dist_norm = double(max_peak_dist_norm(1));
    if ~isfinite(max_peak_dist_norm) || max_peak_dist_norm < 0
        max_peak_dist_norm = defaultGaussCenterRadiusNormLocal(rew.gauss_center_positions_norm);
    end
end

gauss_center_free = false;
if isfield(rew, 'gauss_center_free') && ~isempty(rew.gauss_center_free)
    gauss_center_free = logical(rew.gauss_center_free(1));
end

if ~isfield(rew, 'gauss_center_mode') || isempty(rew.gauss_center_mode)
    rew.gauss_center_mode = 'random'; % backward-compatible default
end
if ~strcmpi(rew.gauss_center_mode, 'random') && ~strcmpi(rew.gauss_center_mode, 'manual')
    rew.gauss_center_mode = 'random'; % fallback for invalid values
end

if gauss_center_free
    if ~isfield(rew, 'gauss_center_coords') || isempty(rew.gauss_center_coords) || ...
            numel(rew.gauss_center_coords) < 2 || any(~isfinite(rew.gauss_center_coords(1:2)))
        rew.gauss_center_coords = sampleFreeGaussCenterCoordsLocal(max_peak_dist_norm);
    else
        rew.gauss_center_coords = double(rew.gauss_center_coords(1:2));
    end
    selected_center_norm = constrainCenterCoordsLocal(rew.gauss_center_coords(:)', max_peak_dist_norm);
    rew.gauss_center_coords = selected_center_norm;
else
    if isfield(rew, 'gauss_center_coords') && ~isempty(rew.gauss_center_coords) && ...
            numel(rew.gauss_center_coords) >= 2 && all(isfinite(rew.gauss_center_coords(1:2)))
        rew.gauss_center_coords = double(rew.gauss_center_coords(1:2));
    else
        rew.gauss_center_coords = [NaN NaN];
    end

    n_gauss_centers = size(rew.gauss_center_positions_norm, 1);
    if strcmpi(rew.gauss_center_mode, 'manual')
        if ~isfield(rew, 'gauss_center_idx') || isempty(rew.gauss_center_idx)
            rew.gauss_center_idx = 1; % center default in manual mode
        end
        rew.gauss_center_idx = max(1, min(n_gauss_centers, round(rew.gauss_center_idx)));
    else
        if ~isfield(rew, 'gauss_center_idx') || isempty(rew.gauss_center_idx)
            rew.gauss_center_idx = randi(n_gauss_centers);
        end
    end

    selected_center_norm = rew.gauss_center_positions_norm(rew.gauss_center_idx, :);
end

center_px = round(selected_center_norm .* (gauss_dim - 1)) + 1;
center_px = max(1, min(gauss_dim, center_px));

end


function coords = sampleFreeGaussCenterCoordsLocal(radius_norm)
center_origin = [0.5, 0.5];
if ~isfinite(radius_norm) || radius_norm <= 0
    coords = center_origin;
    return
end

% Uniform draw over the visible [0,1] area constrained to the current
% Gaussian-center radius.
coords = center_origin;
for attempt = 1:1000 %#ok<NASGU>
    candidate = rand(1, 2);
    if norm(candidate - center_origin) <= radius_norm
        coords = candidate;
        return
    end
end

theta = rand * 2 * pi;
r = sqrt(rand) * min(radius_norm, 0.5);
coords = center_origin + r * [cos(theta), sin(theta)];
coords = max(0, min(1, coords));
end


function coords = constrainCenterCoordsLocal(coords, radius_norm)
center_origin = [0.5, 0.5];
coords = max(0, min(1, double(coords(1:2))));
if ~isfinite(radius_norm) || radius_norm <= 0
    coords = center_origin;
    return
end

offset = coords - center_origin;
offset_norm = norm(offset);
if offset_norm > radius_norm
    coords = center_origin + offset ./ offset_norm .* radius_norm;
    coords = max(0, min(1, coords));
end
end


function radius_norm = defaultGaussCenterRadiusNormLocal(center_positions_norm)
center_positions_norm = double(center_positions_norm);
center_origin = [0.5, 0.5];
if isempty(center_positions_norm) || size(center_positions_norm, 2) < 2
    radius_norm = 0;
    return
end

offsets = center_positions_norm(:, 1:2) - center_origin;
radius_norm = max(sqrt(sum(offsets .^ 2, 2)));
if ~isfinite(radius_norm) || radius_norm < 0
    radius_norm = 0;
end
end
