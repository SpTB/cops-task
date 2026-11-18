function texparams = struct2params(texstruct)
% function texparams = struct2params(texstruct);
%
% converts the structure output of textureAnalysis.m (from the Portilla &
% Simoncelli texture model) into a vector of parameters
%
% created by freeman and yan, 3/10
% modified by freeman, 5/11

fields = fieldnames(texstruct); 

ln = 0;
for i=1:length(fields),  ln = ln + prod(size(fields{i})); end;
texparams = zeros(ln,1);

ix = 1;
for i=1:length(fields),
  lni = eval(['prod(size(texstruct.' fields{i} '));']);
  eval(['texparams(ix:ix+lni-1) = texstruct.' fields{i} '(:);']);
  ix = ix + lni;
end;
