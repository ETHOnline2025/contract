import { utils } from 'ethers';
import { addressToBytes32 } from './addresses.js';
export function domainHash(domain, merkle_tree_hook) {
    return utils.solidityKeccak256(['uint32', 'bytes32', 'string'], [domain, addressToBytes32(merkle_tree_hook), 'HYPERLANE']);
}
//# sourceMappingURL=domains.js.map