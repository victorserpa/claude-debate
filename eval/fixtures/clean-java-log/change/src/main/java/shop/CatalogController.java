package shop;

import java.util.List;
import java.util.logging.Logger;

public class CatalogController {
    private static final Logger LOG = Logger.getLogger("catalog");
    private final Catalog catalog;

    public CatalogController(Catalog catalog) { this.catalog = catalog; }

    public List<String> list() {
        List<String> all = catalog.all();
        LOG.info("catalog served: " + all.size() + " products");
        return all;
    }
}
