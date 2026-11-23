function fs = inferFs(ex)
fs = 500;
if isfield(ex, 'setup') && isfield(ex.setup, 'adc') && isfield(ex.setup.adc, 'Rate') && isfinite(ex.setup.adc.Rate)
    fs = ex.setup.adc.Rate;
end
end
