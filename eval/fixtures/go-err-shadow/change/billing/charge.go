package billing

// Settle charges the order; a zero total needs no charge.
func Settle(g Gateway, o *Order) error {
	var err error
	if o.Total > 0 {
		id, err := g.Charge(o.Total)
		if err == nil {
			o.ChargeID = id
		}
	}
	if err != nil {
		return err
	}
	o.Paid = true
	return nil
}
