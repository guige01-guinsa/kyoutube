// Private buyer/supplier certificates, including abandoned uploads.
export async function deleteBusinessDocuments(admin: any, userId: string): Promise<void> {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(userId)) throw new Error('invalid_document_owner');
  const bucket = admin.storage.from('purchase-business-documents');
  const paths: string[] = [];
  for (let offset = 0; ; offset += 100) {
    const {data,error} = await bucket.list(userId,{limit:100,offset,sortBy:{column:'name',order:'asc'}});
    if(error) throw new Error('business_document_list_failed');
    for (const entry of data ?? []) {
      if(entry.name === '.emptyFolderPlaceholder') continue;
      if(!entry.id || typeof entry.name !== 'string' || !/^[0-9a-f-]{36}\.png$/.test(entry.name)) throw new Error('invalid_business_document_path');
      paths.push(`${userId}/${entry.name}`);
      if(paths.length>10000) throw new Error('business_document_cleanup_limit');
    }
    if((data?.length ?? 0)<100) break;
  }
  for(let i=0;i<paths.length;i+=100) {
    const {error}=await bucket.remove(paths.slice(i,i+100));
    if(error) throw new Error('business_document_remove_failed');
  }
}
