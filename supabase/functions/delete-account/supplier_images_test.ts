import { deleteSupplierImages } from "./supplier_images.ts";
const user = "98000000-0000-4000-8000-000000000001";
function fixture(fail = false, malicious = false) {
  const removed: string[] = [];
  return {
    removed,
    admin: {
      storage: {
        from: (name: string) => {
          if (name !== "supplier-products") throw Error("wrong bucket");
          return {
            list: async (prefix: string) => ({
              data: prefix === user
                ? [{ id: null, name: malicious ? "../other" : "business" }]
                : [{ id: "image", name: "photo.jpg" }],
              error: fail ? Error("offline") : null,
            }),
            remove: async (paths: string[]) => {
              removed.push(...paths);
              return { error: null };
            },
          };
        },
      },
    },
  };
}
Deno.test("catalog cleanup remains within the authenticated owner's prefix", async () => {
  const f = fixture();
  await deleteSupplierImages(f.admin, user);
  if (
    JSON.stringify(f.removed) !== JSON.stringify([`${user}/business/photo.jpg`])
  ) throw Error("wrong paths");
});
for (const kind of ["list failure", "path traversal"]) {
  Deno.test(`catalog cleanup rejects ${kind}`, async () => {
    const f = fixture(kind === "list failure", kind === "path traversal");
    let rejected = false;
    try {
      await deleteSupplierImages(f.admin, user);
    } catch {
      rejected = true;
    }
    if (!rejected || f.removed.length) throw Error("unsafe cleanup");
  });
}
