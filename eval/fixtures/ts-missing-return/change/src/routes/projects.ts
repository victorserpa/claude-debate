import { Router } from "express";
import { db } from "../db";

export const projects = Router();

projects.delete("/:id", async (req, res) => {
  if (!req.user?.isAdmin) {
    res.status(403).json({ error: "admins only" });
  }
  await db.project.delete({ where: { id: req.params.id } });
  res.status(204).end();
});
