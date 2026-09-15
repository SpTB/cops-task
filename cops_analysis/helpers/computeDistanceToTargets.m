function distPx = computeDistanceToTargets(xPx, yPx, targetX, targetY, inBounds)
distPx = hypot(xPx - targetX, yPx - targetY);
distPx(~inBounds | ~isfinite(targetX) | ~isfinite(targetY)) = NaN;
end
