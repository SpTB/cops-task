function ex = saveCoPsSessionx(ex,outputFile)
% Save raw data first; add the offline audit without risking that saved copy.
outputFile=char(outputFile);
[folder,name,ext]=fileparts(outputFile);
if isempty(folder), folder=pwd; end
if isempty(ext), ext='.mat'; end
outputFile=fullfile(folder,[name ext]);
ex.frameAudit=struct('schemaVersion',1,'status','pending');
savePayloadLocal(outputFile,ex);
fprintf('Session data saved. Running offline VBL/photodiode frame audit...\n');
try
    ex=auditCoPsFrameTimingx(ex);
catch err
    ex.frameAudit=struct('schemaVersion',1,'status','failed', ...
        'errorIdentifier',err.identifier,'message',err.message);
    warning('CoPsFrameAudit:Failed','Frame audit failed; raw session is saved: %s',err.message);
end
% Write the enriched file alongside the raw one, then replace it only after
% the write succeeds. Failure here leaves the raw session available.
temporary=[tempname(folder) '.mat'];
cleanup=onCleanup(@() removeTemporaryLocal(temporary));
try
    savePayloadLocal(temporary,ex);
    [ok,message]=movefile(temporary,outputFile,'f');
    assert(ok,'CoPsFrameAudit:Save','%s',message);
catch err
    warning('CoPsFrameAudit:Save','Raw session remains saved; could not persist frame audit: %s',err.message);
end
end

function savePayloadLocal(file,ex)
info=whos('ex');
if info.bytes<1e9
    save(file,'ex');
else
    save(file,'ex','-v7.3');
end
end

function removeTemporaryLocal(file)
if isfile(file), delete(file); end
end
