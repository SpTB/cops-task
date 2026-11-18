function texstruct = params2struct(texparams, Nsc, Nor, Na)
%
% converts a parameter vector into a structure for use with the Portilla
% and Simoncelli texture model. this function yields a structure
% that will be a valid input to 'textureSynthesis'. 
% inputs must include the scale, number of orientation bands, 
% and neighborhood size.
%
% created by freeman and yan, 3/10
% modified by freeman, 5/11

if nargin<4
    error('(params2struct) must include scale, orietantations, and neighborhood');
end

fsizes = {[1 6],
	 [Nsc+1 2],
	 [Na Na Nsc+1], 
	 [Na Na Nsc Nor],
	 [Nor*Nsc+2 1],
	 [Nor Nor Nsc+1],
	 [Nor Nor Nsc],
	 [max([2*Nor 5]) max([2*Nor 5]) Nsc+1],
	 [2*Nor max([2*Nor 5]) Nsc],
	 [1 1]};
	 

fields = {'pixelStats',
	 'pixelLPStats',
	 'autoCorrReal',
	 'autoCorrMag',
	 'magMeans',
	 'cousinMagCorr',
	 'parentMagCorr',
	 'cousinRealCorr',
	 'parentRealCorr',
	 'varianceHPR' };

ix = 1;
for i=1:length(fields),
  ln = prod(fsizes{i});
  eval(['texstruct.' fields{i} ' = reshape(texparams(ix:ix+ln-1),[' num2str(fsizes{i}) ']);']);
  ix = ix + ln;
end;
