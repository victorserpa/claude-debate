package shop;

import java.util.List;

public class Catalog {
    private final List<String> products;

    public Catalog(List<String> products) { this.products = products; }

    public List<String> all() {
        return products;
    }
}
