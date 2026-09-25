export function registerInvoiceRoutes(app, db) {
  app.get("/invoices/:id", async (req, res) => {
    const invoice = await db.invoices.find(req.params.id);
    if (!invoice) return res.status(404).end();
    if (invoice.ownerId !== req.user.id) return res.status(403).end();
    res.json(invoice);
  });

  app.delete("/invoices/:id", async (req, res) => {
    const invoice = await db.invoices.find(req.params.id);
    if (!invoice) return res.status(404).end();
    await db.invoices.remove(invoice.id);
    res.status(204).end();
  });
}
