(async()=>{
 const manifest=chrome.runtime.getManifest();
 const required={...manifest,optional_host_permissions:[],host_permissions:['https://*/*','http://*/*']};
 const value={version:navigator.userAgent,optionalManifestWarnings:await chrome.management.getPermissionWarningsByManifest(JSON.stringify(manifest)),requiredAllSitesWarnings:await chrome.management.getPermissionWarningsByManifest(JSON.stringify(required)),permissions:await chrome.permissions.getAll(),state:await chrome.runtime.sendMessage({op:'status'}),lastRead:(await chrome.storage.local.get('lastRead')).lastRead};
 document.getElementById('out').textContent=JSON.stringify(value,null,2);
})();
