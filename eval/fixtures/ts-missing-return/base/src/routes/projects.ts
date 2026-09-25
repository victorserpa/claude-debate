import { Router } from "express";
import { db } from "../db";

export const projects = Router();

projects.delete("/:id", async (req, res) => {
  await db.project.delete({ where: { id: req.params.id } });
  res.status(204).end();
});
