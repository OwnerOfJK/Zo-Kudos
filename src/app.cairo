use dojo::world::{IWorldDispatcher, IWorldDispatcherTrait};
use pixelaw::core::models::pixel::{Pixel, PixelUpdate};
use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};
use starknet::{get_caller_address, get_contract_address, get_execution_info, ContractAddress};

#[starknet::interface]
trait IZoKudosActions<TContractState> {
    fn init(self: @TContractState);
    fn interact(self: @TContractState, default_params: DefaultParameters, field_size: u32);
    fn place(self: @TContractState, default_params: DefaultParameters);
}

/// APP_KEY must be unique across the entire platform
const APP_KEY: felt252 = 'zokudos';

/// Core only supports unicode icons for now
const APP_ICON: felt252 = 'U+263A';

/// prefixing with BASE means using the server's default manifest.json handler
const APP_MANIFEST: felt252 = 'BASE/manifests/zokudos';

#[derive(Model, Copy, Drop, Serde, SerdeLen)]
struct ZoKudosField {
    #[key]
    x: u32,
    #[key]
    y: u32,
    index: u8,
    state: u8
}

#[dojo::contract]
/// contracts must be named as such (APP_KEY + underscore + "actions")
mod zokudos_actions {
    use starknet::{
        get_tx_info, get_caller_address, get_contract_address, get_execution_info, ContractAddress
    };

    use super::IZoKudosActions;
    use pixelaw::core::models::pixel::{Pixel, PixelUpdate};

    use pixelaw::core::models::permissions::{Permission};
    use pixelaw::core::actions::{
        IActionsDispatcher as ICoreActionsDispatcher,
        IActionsDispatcherTrait as ICoreActionsDispatcherTrait
    };
    use super::{APP_KEY, APP_ICON, APP_MANIFEST, ZoKudosField};
    use pixelaw::core::utils::{get_core_actions, Direction, Position, DefaultParameters};

    use debug::PrintTrait;

    // impl: implement functions specified in trait
    #[external(v0)]
    impl ActionsImpl of IZoKudosActions<ContractState> {
        /// Initialize the MyApp App (TODO I think, do we need this??)
        fn init(self: @ContractState) {
            let world = self.world_dispatcher.read();
            let core_actions = pixelaw::core::utils::get_core_actions(world);

            core_actions.update_app(APP_KEY, APP_ICON, APP_MANIFEST);
        }

        /// Put color on a certain position
        ///
        /// # Arguments
        ///
        /// * `position` - Position of the pixel.
        /// * `new_color` - Color to set the pixel to.
        fn interact(self: @ContractState, default_params: DefaultParameters, field_size: u32) {
            'put_field'.print();

            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            // Load the Pixel
            let mut pixel = get!(world, (position.x, position.y), (Pixel));

            try_field_setup(
                world,
                core_actions,
                get_contract_address(),
                player,
                position,
                default_params.color,
                field_size
            );

            'interact: done'.print();
        }

        fn place(self: @ContractState, default_params: DefaultParameters) {
            'place: start'.print();
            // Load important variables
            let world = self.world_dispatcher.read();
            let core_actions = get_core_actions(world);
            let position = default_params.position;
            let player = core_actions.get_player_address(default_params.for_player);
            let system = core_actions.get_system_address(default_params.for_system);

            // Load the Pixel that was clicked
            let mut pixel = get!(world, (position.x, position.y), (Pixel));

            // Ensure the clicked pixel is a ZoKudos Pixel
            pixel.app.print();
            assert(pixel.app == get_contract_address(), 'not a ZoKudos app pixel');

            // And load the corresponding GameField
            let mut field = get!(world, (position.x, position.y), ZoKudosField);

            // Ensure this pixel was not already used for a move
            // assert(field.state == 0, 'field already set'); I commented this assert out for now.

            // Process the player's move
            field.state = 1;
            set!(world, (field));

            // We can now update color of the pixel
            core_actions
                .update_pixel(
                    player,
                    system,
                    PixelUpdate {
                        x: position.x,
                        y: position.y,
                        color: Option::Some(default_params.color),
                        timestamp: Option::None,
                        text: Option::None,
                        app: Option::None,
                        owner: Option::Some(player),
                        action: Option::Some('none')
                    }
                );
        }
    }

    fn try_field_setup(
        world: IWorldDispatcher,
        core_actions: ICoreActionsDispatcher,
        system: ContractAddress,
        player: ContractAddress,
        position: Position,
        color: u32,
        field_size: u32
    ) {
        let mut x: u32 = 0;
        let mut y: u32 = 0;
        loop {
            if x >= field_size {
                break;
            }
            y = 0;
            loop {
                if y >= field_size {
                    break;
                }

                let pixel = get!(world, (position.x + x, position.y + y), Pixel);
                assert(
                    pixel.owner.is_zero(), 'Find an unoccupied space.'
                );

                y += 1;
            };
            x += 1;
        };

        x = 0;
        y = 0;
        let mut index = 0;

        loop {
            if x >= field_size {
                break;
            }
            y = 0;
            loop {
                if y >= field_size {
                    break;
                }

                core_actions
                    .update_pixel(
                        player,
                        system,
                        PixelUpdate {
                            x: position.x + x,
                            y: position.y + y,
                            color: Option::Some(color),
                            timestamp: Option::None,
                            text: Option::None,
                            app: Option::Some(system),
                            owner: Option::Some(player),
                            action: Option::Some('place'),
                        }
                    );

                set!(
                    world, (ZoKudosField { x: position.x + x, y: position.y + y, index, state: 0 })
                );

                index += 1;
                y += 1;
            };
            x += 1;
        };
    }
}
