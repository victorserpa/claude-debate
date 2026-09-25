export function registerInvoiceRoutes(app, db) {
  app.get("/invoices/:id", async (req, res) => {
    const invoice = await db.invoices.find(req.params.id);
    if (!invoice) return res.status(404).end();
    if (invoice.ownerId !== req.user.id) return res.status(403).end();
    res.json(invoice);
  });
}
