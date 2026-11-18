function out = randomize_phase(oim, stdz)
r = vec(abs(fftshift(fft2(oim))));
noise = randn(size(oim));
tmpFFT = vec(fftshift(fft2(noise)));
tmpTheta = angle(tmpFFT);
tmpAdjFFT = reshape(complex(r.*cos(tmpTheta),r.*sin(tmpTheta)),size(oim,1),size(oim,2));
out = (ifft2(ifftshift(tmpAdjFFT),'symmetric'));
test = (ifft2(ifftshift(tmpAdjFFT)));
if sum(imag(test(:))) > 10E-8
warning('non-trivial imaginary component');
end
%standarized output
if stdz==1
    out = (out-mean(out(:)))/std(out(:));
end

function out = vec(in)
out = in(:);

