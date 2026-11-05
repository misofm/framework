module witness_new_probe::probe;

use record_sale::witness::{Self, Witness};

public fun forge(): Witness {
    witness::new()
}
