// Remove only this account's catalog images, including abandoned uploads.
// Storage deletion uses the API, never deletes metadata without the file.
export async function deleteSupplierImages(
  admin: any,
  userId: string,
): Promise<void> {
  if (!/^[0-9a-f-]{36}$/.test(userId)) throw new Error("invalid_image_owner");
  const bucket = admin.storage.from("supplier-products");
  const pending = [userId];
  const paths: string[] = [];
  while (pending.length) {
    const prefix = pending.pop()!;
    for (let offset = 0;; offset += 100) {
      const { data, error } = await bucket.list(prefix, {
        limit: 100,
        offset,
        sortBy: { column: "name", order: "asc" },
      });
      if (error) throw new Error("supplier_image_list_failed");
      const entries = data ?? [];
      for (const entry of entries) {
        if (entry.name === ".emptyFolderPlaceholder") continue;
        if (
          typeof entry.name !== "string" ||
          !/^[a-zA-Z0-9._-]+$/.test(entry.name) || entry.name === "." ||
          entry.name === ".."
        ) throw new Error("invalid_supplier_image_path");
        const path = `${prefix}/${entry.name}`;
        if (entry.id != null) paths.push(path);
        else if (prefix === userId) pending.push(path);
        else throw new Error("unexpected_supplier_image_depth");
        if (paths.length + pending.length > 10000) {
          throw new Error("supplier_image_cleanup_limit");
        }
      }
      if (entries.length < 100) break;
    }
  }
  for (let i = 0; i < paths.length; i += 100) {
    const { error } = await bucket.remove(paths.slice(i, i + 100));
    if (error) throw new Error("supplier_image_remove_failed");
  }
}
