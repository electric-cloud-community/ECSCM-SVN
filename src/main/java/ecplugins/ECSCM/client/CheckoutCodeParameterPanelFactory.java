
package ecplugins.ECSCM.client;

import com.google.gwt.core.client.JavaScriptObject;

import com.electriccloud.commander.gwt.client.Component;
import com.electriccloud.commander.gwt.client.ComponentBaseFactory;
import com.electriccloud.commander.gwt.client.ComponentContext;
import org.jetbrains.annotations.NotNull;

public class CheckoutCodeParameterPanelFactory extends ComponentBaseFactory
{
    @NotNull
    @Override 
    public Component createComponent(ComponentContext jso)
    {
        return new CheckoutCodeParameterPanel();
    }
}
