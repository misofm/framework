module witness_pack_probe::probe;

use record_sale::witness::Witness;

public fun forge(): Witness {
    Witness()
}
