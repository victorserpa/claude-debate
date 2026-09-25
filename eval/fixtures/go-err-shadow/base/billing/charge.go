package billing

func Settle(g Gateway, o *Order) error {
	id, err := g.Charge(o.Total)
	if err != nil {
		return err
	}
	o.ChargeID = id
	o.Paid = true
	return nil
}
